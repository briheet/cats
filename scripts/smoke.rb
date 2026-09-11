require 'json'
require 'tmpdir'
require 'fileutils'
require 'timeout'

def eventually(seconds = 12)
  Timeout.timeout(seconds) do
    loop do
      result = yield
      return result if result
      sleep 0.1
    end
  end
end

binary = File.expand_path('../target/release/cats-llm', __dir__)
root = File.expand_path('..', __dir__)
report = {}
Dir.mktmpdir('cats-smoke-') do |dir|
  claude = File.join(dir, 'claude', 'projects')
  codex = File.join(dir, 'codex', 'sessions')
  data = File.join(dir, 'data')
  FileUtils.mkdir_p([claude, codex])
  config = File.join(dir, 'config.toml')
  File.write(config, "theme = 'nord'\nbudget-usd = 25\n")
  env = { 'CATS_LLM_CONFIG' => config, 'CATS_LLM_BUDGET_USD' => nil, 'CATS_LLM_DATA_DIR' => data, 'CLAUDE_CONFIG_DIR' => File.dirname(claude), 'CODEX_HOME' => File.dirname(codex), 'RUST_LOG' => 'cats_llm=debug' }
  %w[claude codex].each do |provider|
    rows = File.readlines(File.join(root, 'crates/cats-llm/tests/fixtures', "#{provider}.jsonl"))
    File.open(File.join(provider == 'claude' ? claude : codex, 'fixture.jsonl'), 'w') do |file|
      rows.each { |line| row = JSON.parse(line); row['timestamp'] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'); file.puts(JSON.generate(row)) }
    end
  end
  log = File.open(File.join(dir, 'profile.log'), 'w+')
  collector = Process.spawn(env, binary, '--profile', out: log, err: log)
  runner = nil
  begin
    snapshot = File.join(data, 'state.json')
    read_state = -> { JSON.parse(File.read(snapshot)) rescue nil }
    state = eventually { value = read_state.call; value if value && value.dig('today', 'tokens_total') == 3850 }
    report['initial_tokens'] = state.dig('today', 'tokens_total')
    raise 'Configured theme or budget missing from snapshot' unless state.dig('theme', 'colors', 'surface') == '#2e3440' && state.dig('today', 'budget_usd') == 25
    report['configured_snapshot'] = true
    second = Process.spawn(env, binary, '--once', out: File::NULL, err: File::NULL)
    _, second_status = Process.wait2(second)
    raise 'Duplicate collector acquired the lock' if second_status.success?
    report['single_instance'] = true
    reset = Process.spawn(env, binary, 'reset', '--yes', out: File::NULL, err: File::NULL)
    _, reset_status = Process.wait2(reset)
    raise 'Reset ran while collector held the lock' if reset_status.success?
    raise 'Reset changed live snapshot' unless read_state.call.dig('today', 'tokens_total') == 3850
    report['reset_rejects_live_collector'] = true

    runner = Process.spawn(env, binary, 'run', 'smoke-agent', '--', '/bin/sleep', '120', out: log, err: log)
    status = ->(name) { read_state.call&.fetch('agents', [])&.any? { |a| a['name'] == 'smoke-agent' && a['status'] == name } }
    eventually { status.call('running') }
    %w[pause resume].each do |action|
      puts "Checking #{action}"
      tmp = File.join(data, 'control.tmp')
      File.write(tmp, JSON.generate(action: action))
      File.rename(tmp, File.join(data, 'control.json'))
      eventually { status.call(action == 'pause' ? 'waiting' : 'running') }
    end
    report['live_agent_pause_resume'] = true
    Process.kill('TERM', runner)
    Process.wait(runner)
    runner = nil
    eventually { status.call('failed') }
    if ENV['CATS_LLM_SMOKE_CONFIG'] == '1'
      File.write(config, "theme = 'rose-pine-dawn'\nbudget-usd = 42\n")
      puts 'Checking configuration reload (up to 60 seconds)'
      eventually(70) { value = read_state.call; value&.dig('theme', 'appearance') == 'light' && value.dig('today', 'budget_usd') == 42 }
      report['live_configuration_reload'] = true
      File.write(config, "budget-usd = nan\n")
      puts 'Checking invalid configuration retains last good values (up to 60 seconds)'
      eventually(70) { File.read(log.path).include?('Keeping last valid configuration') }
      value = read_state.call
      raise 'Invalid configuration replaced good values' unless value.dig('theme', 'appearance') == 'light' && value.dig('today', 'budget_usd') == 42
      report['invalid_configuration_retained'] = true
    end
    if ENV['CATS_LLM_SMOKE_PROFILE'] == '1'
      # Let sysinfo observe an actual idle interval between samples.
      sleep 62
    end
    Process.kill('TERM', collector)
    Timeout.timeout(5) { Process.wait(collector) }
    collector = nil
    log.flush
    log.rewind
    report['profile'] = log.read.lines.select { |line| line.include?('profile') || line.include?('latency') }.map { |line| line.gsub(/\e\[[0-9;]*m/, '').strip }
    report['graceful_shutdown'] = true
    unless ENV['CATS_LLM_SMOKE_CONFIG'] == '1'
      reset = Process.spawn(env, binary, 'reset', '--yes', out: log, err: log)
      _, reset_status = Process.wait2(reset)
      raise 'Reset failed' unless reset_status.success?
      raise 'Reset lost available usage' unless read_state.call.dig('today', 'tokens_total') == 3850
      raise 'Reset removed agent sources' if Dir.glob(File.join(data, 'agents', '*.jsonl')).empty?
      report['reset_reimports_usage'] = true
    end
  ensure
    if $!
      warn "Smoke state: #{read_state.call.inspect}" if read_state
      log.flush
      log.rewind
      warn log.read
      Dir.glob(File.join(data, 'agents', '*.jsonl')).each { |path| warn File.read(path) }
    end
    [runner, collector].compact.each do |pid|
      Process.kill('TERM', pid) rescue Errno::ESRCH
      Process.wait(pid) rescue Errno::ECHILD
    end
    log.close
  end
end
FileUtils.mkdir_p(File.join(root, 'build'))
File.write(File.join(root, 'build/smoke-report.json'), JSON.pretty_generate(report))
puts JSON.pretty_generate(report)
