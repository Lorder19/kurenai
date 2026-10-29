# Third-party notices

## Trigram tables (layout detection)

`Sources/Kurenai/Data/trigrams_ru.json` and `trigrams_en.json` come from
[keyswitcher](https://github.com/graninilya/keyswitcher) by Ilya Granin, as shipped with
[Keyboop](https://github.com/iffuno/keyboop). The thresholds for fixing a word mid-word follow Keyboop's
detector. Both projects are MIT licensed:

```
MIT License

Copyright (c) 2026 Ilya Granin
Copyright (c) 2026 Keyboop contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Spelling dictionaries (downloaded only on request)

When a keyboard layout's language has no spelling dictionary in macOS, Kurenai can download the
free Hunspell dictionary for it from [LibreOffice/dictionaries](https://github.com/LibreOffice/dictionaries)
into `~/Library/Spelling`. Each dictionary keeps its own license, listed in its folder there.
