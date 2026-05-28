# Fonts

The app expects three OFL-licensed font families. Drop their `.ttf` files into
this folder — `Theme.registerFonts()` registers every `.ttf` here at launch via
`CTFontManagerRegisterFontsForURLs`. No Info.plist entry needed.

## Required families

| Family               | Weights        | Source                                                                |
| -------------------- | -------------- | --------------------------------------------------------------------- |
| Bricolage Grotesque  | 500, 600, 700, 800 | https://fonts.google.com/specimen/Bricolage+Grotesque              |
| Geist                | 400, 500, 600, 700 | https://vercel.com/font (download → "Geist Sans" zip)              |
| Geist Mono           | 400, 500, 600      | same zip, "Geist Mono" subfolder                                   |

## Naming

xcodegen picks up any file matching `Resources/Fonts/**/*.ttf`. Either flat
files or per-family subfolders work; the loader doesn't care about layout.

Suggested layout (matches what most downloads ship):

```
Resources/Fonts/
  BricolageGrotesque/
    BricolageGrotesque-Medium.ttf
    BricolageGrotesque-SemiBold.ttf
    BricolageGrotesque-Bold.ttf
    BricolageGrotesque-ExtraBold.ttf
  Geist/
    Geist-Regular.ttf
    Geist-Medium.ttf
    Geist-SemiBold.ttf
    Geist-Bold.ttf
  GeistMono/
    GeistMono-Regular.ttf
    GeistMono-Medium.ttf
    GeistMono-SemiBold.ttf
```

## Fallback

Without these files the app still runs — every `Theme.body(_:)` /
`Theme.display(_:)` call quietly falls back to the system font. The UI is
visually plainer but functional.
