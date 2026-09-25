# The logo

`tools/logo-source.png` is the artwork as supplied: the climber with her
skeleton drawn over her, a wall beside her, and the wordmark underneath, printed
blue on cream.

`MakeLogoAssets.swift` cuts four things out of it and writes each straight into
its own set in the asset catalog. Rerun it whenever the artwork changes:

```
cd "Climbing App/tools"
swift MakeLogoAssets.swift logo-source.png "../Climbing App/Assets.xcassets"
```

- **icon-1024.png** the figure alone, opaque, on the artwork's own paper.
- **mark.png** the figure alone with a transparent background.
- **lockup.png** the whole thing, mark and word, transparent.
- **wordmark.png** the word alone, transparent, for the Home masthead.

## Why it measures instead of using fixed numbers

Every boundary is found by looking at the pixels: the leftmost ink anywhere, the
row the wordmark starts on, the box around the figure. Drop in a new version of
the artwork at a different size or crop and this still finds them.

The wordmark is located by where it sits horizontally, not by a gap. There is no
clear band of empty rows between the figure and the word, because the wall's
bottom and the word's top overlap vertically; what separates them is that below
the figure's hips she is entirely on the right of the frame, so ink appearing on
the left of the lower third is the word.

Cutting the word out on its own needs that overlap handled rather than measured
around: the wall's bottom tail runs down past the top of the T. In those rows the
word is entirely on the left of the frame and the wall entirely on the right, so
the tool finds the row where the word's second letter starts and drops everything
on the right above it. Cropping below the tail instead would take the top off the
T.

## Why the ink is matted rather than cropped

The paper in the artwork is a photographed texture, not a flat color. Pasting a
crop of it onto a sampled color leaves a visible rectangle. So each pixel's
distance from the paper tone becomes its alpha, which gives the stipple and the
rough edges of the print partial coverage instead of a hard cutout, and keeps
the ink's own colors.

The icon's background is a stretch of the artwork's own clean left margin, for
the same reason. That margin is measured against the leftmost ink **including
the wordmark**: measuring it against the figure alone pulls the word's T into
the patch and stretches a blue smear across the whole icon.

## Sizes

This is a stippled print, not a geometric glyph, and it needs room. Below about
forty points the texture stops resolving and the figure becomes a smudge, which
is why the masthead mark is 46 and not the 30 a drawn icon would have used.
