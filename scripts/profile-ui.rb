#!/usr/bin/env ruby
# Profiles only a synthetic UI process and collector in temporary storage.
require 'json'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'time'

root = File.expand_path('..', __dir__)
output = File.join(root, 'build', 'profiling')
FileUtils.mkdir_p(output)
clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
Dir.mktmpdir('cats-profile-') do |dir|
  FileUtils.mkdir_p(File.join(dir, 'codex'))
  FileUtils.mkdir_p(File.join(dir, 'claude'))
  config = File.join(dir, 'config.toml')
  File.write(config, "codex-dir = #{File.join(dir, 'codex').to_json}\nclaude-dir = #{File.join(dir, 'claude').to_json}\n")
  now = Time.now.to_i
  File.open(File.join(dir, 'codex', 'workload.jsonl'), 'w') do |file|
    file.puts JSON.generate(timestamp: Time.at(now - 20_000).utc.iso8601, type: 'turn_context', payload: {model: 'gpt-5.4'})
    20_000.times do |i|
      file.puts JSON.generate(timestamp: Time.at(now - 20_000 + i).utc.iso8601, type: 'event_msg', payload: {type: 'token_count', info: {total_token_usage: {input_tokens: (i + 1) * 100, output_tokens: (i + 1) * 20}}})
    end
  end
  report = {platform: `uname -sm`.strip, records: 20_000, ui_poll_seconds: 5}
  ['import', 'unchanged'].each do |phase|
    started = clock.call
    log, status = Open3.capture2e('/usr/bin/time', '-l', File.join(root, 'target/release/cats'), '--config', config, '--data-dir', dir, '--once', '--profile')
    raise log unless status.success?
    File.write(File.join(output, "collector-#{phase}.log"), log)
    report["collector_#{phase}_seconds"] = clock.call - started
  end
  count, status = Open3.capture2('/usr/bin/sqlite3', File.join(dir, 'cats.sqlite'), 'SELECT COUNT(*) FROM events')
  raise 'Workload was not fully ingested' unless status.success? && count.to_i == 20_000
  report[:verified_events] = count.to_i
  state = JSON.parse(File.read(File.join(root, 'macos/Tests/Fixtures/state.json')))
  snapshot = File.join(dir, 'cats-state.json')
  File.write(snapshot, JSON.generate(state))
  File.write(File.join(dir, 'heartbeat'), Time.now.to_i.to_s)
  widgets = ENV.fetch('CATS_WIDGETS', 'large,medium,small')
  report[:widgets] = widgets
  env = {'CATS_DATA_DIR' => dir, 'CATS_EXTERNAL_COLLECTOR' => '1', 'CATS_WIDGETS' => widgets}
  ui = File.join(root, 'build/Build/Products/Release/Cats.app/Contents/MacOS/Cats')
  pid = Process.spawn(env, ui, out: File.join(output, 'ui.log'), err: [:child, :out])
  begin
    sleep 5
    measure = lambda do
      text, status = Open3.capture2('ps', '-p', pid.to_s, '-o', 'time=', '-o', 'rss=')
      raise 'UI exited during profiling' unless status.success?
      cpu, rss = text.split
      seconds = cpu.split(':').inject(0.0) { |total, part| total * 60 + part.to_f }
      [seconds, rss.to_i]
    end
    samples = [measure.call]
    start = clock.call
    14.times do |i|
      state['generated_at'] = Time.now.to_i
      state['today']['spend_usd'] = 13.62 + i * 0.01
      File.write(snapshot + '.tmp', JSON.generate(state))
      File.rename(snapshot + '.tmp', snapshot)
      File.write(File.join(dir, 'heartbeat'), Time.now.to_i.to_s)
      sleep 5
      samples << measure.call
    end
    elapsed = clock.call - start
    report[:ui_seconds] = elapsed
    report[:ui_cpu_seconds] = samples.last[0] - samples.first[0]
    report[:ui_average_cpu_percent] = report[:ui_cpu_seconds] * 100 / elapsed
    report[:ui_peak_rss_kib] = samples.map(&:last).max
    report[:ui_rss_growth_kib] = samples.last[1] - samples.first[1]
    sample_log, sample_status = Open3.capture2e('/usr/bin/sample', pid.to_s, '2', '-file', File.join(output, 'ui-sample.txt'))
    report[:stack_sample_success] = sample_status.success?
    File.write(File.join(output, 'sample.log'), sample_log)
    File.write(File.join(output, 'report.json'), JSON.pretty_generate(report))
    puts JSON.pretty_generate(report)
  ensure
    Process.kill('TERM', pid) rescue Errno::ESRCH
    Process.wait(pid)
  end
end
