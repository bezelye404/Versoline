import Foundation

/// The few colors the widget needs from each of the app's palettes. Compiled into the app and the widget, so it
/// uses no UI types; `WidgetPaletteTests` checks the numbers against `AppColorPalette` so the two cannot drift.
struct WidgetPalette: Equatable {

    struct RGB: Equatable {
        let red: Double
        let green: Double
        let blue: Double
    }

    /// One color for the light appearance and one for the dark one.
    struct Pair: Equatable {
        let light: RGB
        let dark: RGB
        init(_ light: RGB, _ dark: RGB) { self.light = light; self.dark = dark }
        init(_ both: RGB) { self.light = both; self.dark = both }
    }

    let accent: Pair
    let bookmark: Pair
    let background: Pair

    /// Raw values of `AppColorPalette`, in the order the app lists them.
    static let names = ["slate", "sepia", "sage", "dusk", "monochrome", "nordic", "espresso", "matcha", "bordeaux", "solarized"]

    static func named(_ name: String?) -> WidgetPalette {
        table[name ?? ""] ?? table["slate"]!
    }

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> RGB { RGB(red: red, green: green, blue: blue) }

    private static let table: [String: WidgetPalette] = [
        "slate": WidgetPalette(accent: Pair(rgb(0.30, 0.46, 0.62)), bookmark: Pair(rgb(0.80, 0.58, 0.26)),
                               background: Pair(rgb(0.97, 0.98, 0.99), rgb(0.13, 0.14, 0.16))),
        "sepia": WidgetPalette(accent: Pair(rgb(0.66, 0.40, 0.24)), bookmark: Pair(rgb(0.72, 0.45, 0.20)),
                               background: Pair(rgb(0.96, 0.94, 0.89), rgb(0.17, 0.15, 0.12))),
        "sage": WidgetPalette(accent: Pair(rgb(0.32, 0.50, 0.40)), bookmark: Pair(rgb(0.68, 0.55, 0.28)),
                              background: Pair(rgb(0.96, 0.97, 0.95), rgb(0.13, 0.15, 0.13))),
        "dusk": WidgetPalette(accent: Pair(rgb(0.48, 0.40, 0.62)), bookmark: Pair(rgb(0.74, 0.52, 0.38)),
                              background: Pair(rgb(0.97, 0.96, 0.98), rgb(0.15, 0.14, 0.18))),
        // The app draws this palette with the primary text color; these are its light and dark equivalents.
        "monochrome": WidgetPalette(accent: Pair(rgb(0.15, 0.15, 0.15), rgb(0.88, 0.88, 0.88)),
                                    bookmark: Pair(rgb(0.15, 0.15, 0.15), rgb(0.88, 0.88, 0.88)),
                                    background: Pair(rgb(0.98, 0.98, 0.98), rgb(0.12, 0.12, 0.12))),
        "nordic": WidgetPalette(accent: Pair(rgb(0.36, 0.48, 0.60)), bookmark: Pair(rgb(0.78, 0.62, 0.38)),
                                background: Pair(rgb(0.97, 0.98, 0.99), rgb(0.13, 0.15, 0.18))),
        "espresso": WidgetPalette(accent: Pair(rgb(0.68, 0.46, 0.24)), bookmark: Pair(rgb(0.72, 0.40, 0.22)),
                                  background: Pair(rgb(0.98, 0.96, 0.93), rgb(0.15, 0.13, 0.11))),
        "matcha": WidgetPalette(accent: Pair(rgb(0.34, 0.48, 0.36)), bookmark: Pair(rgb(0.74, 0.60, 0.32)),
                                background: Pair(rgb(0.96, 0.97, 0.95), rgb(0.12, 0.15, 0.13))),
        "bordeaux": WidgetPalette(accent: Pair(rgb(0.62, 0.32, 0.38)), bookmark: Pair(rgb(0.76, 0.58, 0.34)),
                                  background: Pair(rgb(0.98, 0.96, 0.97), rgb(0.16, 0.13, 0.15))),
        "solarized": WidgetPalette(accent: Pair(rgb(0.18, 0.50, 0.56)), bookmark: Pair(rgb(0.68, 0.52, 0.16)),
                                   background: Pair(rgb(0.95, 0.93, 0.85), rgb(0.04, 0.19, 0.23))),
    ]
}
