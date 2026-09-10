# Desktop UI revision

Reference: local `9fa8678a-f942-43bb-9da7-bf9c478ccff0.png`.

1. Restore the Cats name without a monogram or descriptive subtitle.
2. Use a wide overview: spend/chart, five bounded agent rows, provider totals.
3. Give small cards a budget ring; keep medium provider rows compact.
4. Increase surface tint for readable glass over detailed wallpaper. Preserve themes.
5. Render real components with zero, one, three, five, and excess agents.
6. Validate dimensions/corners and all card selections; profile isolated UI CPU/RSS
   and collector ingestion. Keep five-second UI polling and unchanged-state suppression.

No synthetic activity descriptions, daily comparisons, or billing accuracy claims.

References: [SwiftUI stacks](https://developer.apple.com/documentation/swiftui/creating-performant-scrollable-stacks)
and [Instruments guidance](https://developer.apple.com/videos/play/wwdc2025/306/).
Five rows use ordinary stacks; lazy layout adds no useful benefit at this size.
