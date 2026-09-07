# ClipBit Privacy Policy

_Last updated: September 7, 2026_

ClipBit is a macOS menu bar utility that shows what kind of content is on your clipboard.
It is designed so that nothing about you or your clipboard leaves your Mac.

## What ClipBit reads

ClipBit reads the system clipboard only when its contents change, in order to show the
matching icon and, when you hover, a short preview. Content that other apps mark as
concealed or transient (for example, passwords copied from a password manager) is never
read or displayed.

## What ClipBit stores

- **Settings** (poll interval, hover delay, thumbnail mode, source-app display) are stored
  in the app's own preferences on your Mac.
- **Temporary files.** When you click to open an image in Preview or text in an editor,
  ClipBit writes a copy to its private cache folder on your Mac so the other app can open
  it. Only the five most recent files are kept. Nothing else from the clipboard is saved,
  and ClipBit keeps no clipboard history.

## Network access

ClipBit makes exactly one kind of network request: when a copied web link is being
previewed, it fetches that site's icon (`/favicon.ico`) from the site's own server so it
can be shown next to the link. This happens only while the preview is on screen, and the
request contains nothing but the standard fetch. ClipBit has no analytics, crash reporting,
advertising, accounts, or servers of its own.

## Data collection

ClipBit does not collect, transmit, sell, or share any personal data.

## Contact

Questions about this policy can be raised at
[github.com/datermine/clipbit/issues](https://github.com/datermine/clipbit/issues).
