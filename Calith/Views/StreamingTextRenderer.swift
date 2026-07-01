// Copyright 2026 Link Dupont
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import SwiftUI

/// A custom TextRenderer that fades in newly streamed characters.
///
/// As `characterCount` increases (driven by animation), glyphs beyond the
/// previous frontier fade from transparent to fully opaque over a small band,
/// producing a smooth "reveal" effect for streaming text.
struct StreamingTextRenderer: TextRenderer, @unchecked Sendable {

    /// The number of characters that should be fully visible.
    /// SwiftUI interpolates this value when animated.
    var characterCount: Double

    /// How many characters wide the fade band is.
    /// Characters within this band transition from 0 to 1 opacity.
    private let fadeBand: Double = 8

    var animatableData: Double {
        get { characterCount }
        set { characterCount = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var index = 0

        for line in layout {
            for run in line {
                for slice in run {
                    let glyphCount = slice.count

                    // Calculate where this slice sits relative to the reveal frontier
                    let sliceEnd = Double(index + glyphCount)
                    let sliceStart = Double(index)

                    if sliceEnd <= characterCount - fadeBand {
                        // Fully revealed — draw at full opacity
                        context.draw(slice)
                    } else if sliceStart >= characterCount {
                        // Not yet revealed — draw invisible
                        var copy = context
                        copy.opacity = 0
                        copy.draw(slice)
                    } else {
                        // Within the fade band — interpolate opacity
                        let progress = (characterCount - sliceStart) / fadeBand
                        let opacity = max(0, min(1, progress))
                        var copy = context
                        copy.opacity = opacity
                        copy.draw(slice)
                    }

                    index += glyphCount
                }
            }
        }
    }
}
