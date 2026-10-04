#!/usr/bin/env python3
"""Turn a saved news page into a small reader-test fixture.

Usage: make-reader-fixture.py page.html out.html "<start of first article paragraph>" "<end of last article paragraph>" [keep ...]

Both snippets must sit inside long (over 60 characters) text nodes. Extra arguments are substrings of boilerplate
lines (legal notices and the like) that should stay verbatim.

Keeps the page structure (tags, class, id, hidden, links, images) and replaces long text nodes with synthetic text:
ART-nn inside the article range, OTH-nn outside it. Short text (menu labels, headings, buttons) is kept so the
tests can check that page furniture is dropped. Scripts, styles, SVG and comments are removed. The result carries
no article prose, so it is safe to commit.
"""
import re
import sys
from html.parser import HTMLParser

DROP = {"script", "style", "svg", "noscript", "iframe", "head", "template"}
KEEP_ATTRS = {"class", "id", "hidden", "href", "src", "srcset", "data-src", "data-srcset", "data-original",
              "data-lazy-src", "alt", "width", "height", "itemprop", "aria-hidden", "data-tag"}
VOID = {"img", "br", "hr", "input", "meta", "link", "source", "wbr"}


def norm(text):
    return re.sub(r"\s+", " ", text.replace(" ", " ")).strip()


class Pass1(HTMLParser):
    """Finds which long text nodes are the first and last article paragraph."""

    def __init__(self, start, end):
        super().__init__(convert_charrefs=True)
        self.start, self.end = norm(start), norm(end)
        self.index = -1
        self.first = self.last = None
        self.skip = 0

    def handle_starttag(self, tag, attrs):
        if tag == "body":
            self.skip = 0  # a head that was never closed
        if tag in DROP:
            self.skip += 1

    def handle_endtag(self, tag):
        if tag in DROP and self.skip:
            self.skip -= 1

    def handle_data(self, data):
        if self.skip:
            return
        text = norm(data)
        if len(text) <= 60:
            return
        self.index += 1
        if self.first is None and self.start in text:
            self.first = self.index
        if self.end in text:
            self.last = self.index


class Pass2(HTMLParser):
    def __init__(self, first, last, keep):
        super().__init__(convert_charrefs=True)
        self.first, self.last, self.keep = first, last, keep
        self.index = -1
        self.art = self.oth = 0
        self.skip = 0
        self.out = []

    def handle_starttag(self, tag, attrs):
        if tag == "body":
            self.skip = 0  # a head that was never closed
        if tag in DROP:
            self.skip += 1
            return
        if self.skip:
            return
        kept = []
        for name, value in attrs:
            if name in KEEP_ATTRS or (name == "style" and value and "display" in value):
                if value is None:
                    kept.append(name)
                else:
                    kept.append('%s="%s"' % (name, value.replace('"', "&quot;")))
        self.out.append("<%s%s>" % (tag, (" " + " ".join(kept)) if kept else ""))

    def handle_endtag(self, tag):
        if tag in DROP:
            if self.skip:
                self.skip -= 1
            return
        if self.skip or tag in VOID:
            return
        self.out.append("</%s>" % tag)

    def handle_data(self, data):
        if self.skip:
            return
        text = norm(data)
        if len(text) <= 60:
            self.out.append(data.replace("<", "&lt;").replace(">", "&gt;"))
            return
        self.index += 1
        if any(k in text for k in self.keep):
            self.out.append(data.replace("<", "&lt;").replace(">", "&gt;"))
            return
        if self.first is not None and self.first <= self.index <= (self.last if self.last is not None else self.index):
            self.art += 1
            label = "ART-%02d" % self.art
        else:
            self.oth += 1
            label = "OTH-%02d" % self.oth
        # Same length as the original so length-based scoring behaves like it does on the real page.
        filler = " lorem ipsum dolor sit amet, consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore"
        body = (label + filler * (len(text) // len(filler) + 1))[: len(text) - 1].rstrip(", ")
        self.out.append(body + ".")


def main():
    source, target, start, end = sys.argv[1:5]
    keep = sys.argv[5:]
    html = open(source, encoding="utf-8", errors="ignore").read()
    one = Pass1(start, end)
    one.feed(html)
    if one.first is None:
        sys.exit("start text not found in a long text node")
    two = Pass2(one.first, one.last, keep)
    two.feed(html)
    result = "".join(two.out)
    open(target, "w", encoding="utf-8").write(result)
    print("%s: %d bytes, %d article paragraphs, %d other long texts" % (target, len(result), two.art, two.oth))


if __name__ == "__main__":
    main()
