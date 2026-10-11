import AppKit
import Testing
@testable import AropytEditor

@Suite("Source view layout")
@MainActor
struct SourceViewLayoutTests {
    @Test func editorUsesPreviewMarginsAtNarrowAndWideWidths() {
        _ = NSApplication.shared
        let controller = SourceViewController()
        let root = controller.view

        root.frame = NSRect(x: 0, y: 0, width: 800, height: 500)
        controller.viewDidLayout()
        #expect(controller.editorTextContainerInset.width == 36)

        root.frame = NSRect(x: 0, y: 0, width: 1100, height: 500)
        controller.viewDidLayout()
        #expect(controller.editorTextContainerInset.width == 90)
        #expect(1100 - 2 * controller.editorTextContainerInset.width == 920)

        #expect(controller.editorTextContainerInset.height == 0)
        #expect(controller.editorLineFragmentPadding == 0)
    }

    @Test func editorUsesOnePointTwoLineHeightWithinParagraphs() {
        _ = NSApplication.shared
        let controller = SourceViewController()
        controller.setText("first wrapped line\nsecond paragraph")

        #expect(
            abs(
                controller.editorParagraphLineHeightMultiple
                    - SourceViewController.lineHeightMultiple
            ) < 0.001
        )
        #expect(SourceViewController.lineHeightMultiple == 1.2)
    }

    @Test func editorShowsLineNumbersAndExpandsTheGutterForMoreDigits() {
        _ = NSApplication.shared
        let controller = SourceViewController()
        controller.setText("first\nsecond")

        #expect(controller.editorShowsLineNumbers)
        let twoLineThickness = controller.editorLineNumberRulerThickness

        controller.setText(Array(repeating: "line", count: 1_000).joined(separator: "\n"))
        #expect(controller.editorLineNumberRulerThickness > twoLineThickness)
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func sourceTextRemainsVisibleBesideLineNumbers(appearanceName: NSAppearance.Name) throws {
        _ = NSApplication.shared
        let controller = SourceViewController()
        let scroll = try #require(controller.view as? NSScrollView)
        let textView = try #require(scroll.documentView as? NSTextView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearanceName)
        window.contentView = scroll
        defer { window.close() }
        scroll.frame = NSRect(x: 0, y: 0, width: 800, height: 500)
        controller.setText("# Visible source\nHello, Markdown 正文。\nthird line")
        scroll.layoutSubtreeIfNeeded()
        controller.viewDidLayout()
        let layoutManager = try #require(textView.layoutManager)
        let textContainer = try #require(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        #expect(textView.frame.width > 0)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: 0, length: 16),
            actualCharacterRange: nil
        )
        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        #expect(glyphRect.width > 0)
        #expect(textView.visibleRect.contains(glyphRect))

        // Checking text storage and layout alone misses an overdrawn editor.
        // Capture the whole scroll view so the ruler is drawn over the text too.
        let bitmap = try #require(scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds))
        scroll.cacheDisplay(in: scroll.bounds, to: bitmap)
        let renderedGlyphRect = scroll.convert(glyphRect, from: textView)
        #expect(try containsVisibleInk(in: renderedGlyphRect, of: scroll, bitmap: bitmap))
    }

    @Test func scrollingInvalidatesTheLineNumberRuler() throws {
        _ = NSApplication.shared
        let controller = SourceViewController()
        let scroll = try #require(controller.view as? NSScrollView)
        let ruler = try #require(scroll.verticalRulerView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        defer { window.close() }
        scroll.frame = NSRect(x: 0, y: 0, width: 800, height: 500)
        controller.setText(Array(repeating: "line", count: 300).joined(separator: "\n"))
        scroll.layoutSubtreeIfNeeded()

        ruler.needsDisplay = false
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 300))
        scroll.reflectScrolledClipView(scroll.contentView)

        #expect(ruler.needsDisplay)
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func scrolledLineNumbersRemainVisibleAndAligned(appearanceName: NSAppearance.Name) throws {
        _ = NSApplication.shared
        let controller = SourceViewController()
        let scroll = try #require(controller.view as? NSScrollView)
        let textView = try #require(scroll.documentView as? NSTextView)
        let ruler = try #require(scroll.verticalRulerView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearanceName)
        window.contentView = scroll
        defer { window.close() }
        scroll.frame = NSRect(x: 0, y: 0, width: 800, height: 500)
        // Include soft wrapping and a final empty line, which has no glyphs.
        let text = (1...200).map { index in
            index.isMultiple(of: 10) ? String(repeating: "wrapped text ", count: 20) : "line \(index)"
        }.joined(separator: "\n") + "\n"
        controller.setText(text)
        scroll.layoutSubtreeIfNeeded()
        controller.viewDidLayout()
        let layoutManager = try #require(textView.layoutManager)
        let textContainer = try #require(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let source = text as NSString
        let bottom = max(0, textView.bounds.height - scroll.contentView.bounds.height)
        #expect(bottom > 2400)

        for offset in [CGFloat(0), 900, 2400, bottom, 0] {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scroll.reflectScrolledClipView(scroll.contentView)
            #expect(abs(scroll.contentView.bounds.minY - offset) < 1)
            let bitmap = try #require(scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds))
            scroll.cacheDisplay(in: scroll.bounds, to: bitmap)

            var checkedLabels = 0
            layoutManager.enumerateLineFragments(
                forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)
            ) { _, usedRect, _, glyphRange, _ in
                let character = layoutManager.characterIndexForGlyph(at: glyphRange.location)
                guard character == 0 || source.character(at: character - 1) == 10 else { return }
                let row = ruler.convert(
                    usedRect.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y),
                    from: textView
                )
                guard row.minY >= ruler.bounds.minY, row.maxY <= ruler.bounds.maxY else { return }
                let labelRect = NSRect(x: 4, y: row.minY, width: ruler.bounds.width - 8, height: row.height)
                let renderedRect = scroll.convert(labelRect, from: ruler)
                #expect(
                    (try? containsVisibleInk(in: renderedRect, of: scroll, bitmap: bitmap)) == true,
                    "Missing line number at scroll offset \(offset), character \(character)"
                )
                checkedLabels += 1
            }
            #expect(checkedLabels > 5)

            if offset == bottom {
                let row = ruler.convert(
                    layoutManager.extraLineFragmentRect.offsetBy(
                        dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y
                    ),
                    from: textView
                )
                #expect(row.minY >= ruler.bounds.minY && row.maxY <= ruler.bounds.maxY)
                let labelRect = NSRect(x: 4, y: row.minY, width: ruler.bounds.width - 8, height: row.height)
                #expect(try containsVisibleInk(
                    in: scroll.convert(labelRect, from: ruler), of: scroll, bitmap: bitmap
                ), "Missing final empty line number")
            }
        }
    }

    private func containsVisibleInk(
        in rect: NSRect,
        of view: NSView,
        bitmap: NSBitmapImageRep
    ) throws -> Bool {
        let scaleX = CGFloat(bitmap.pixelsWide) / view.bounds.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / view.bounds.height
        let top = view.isFlipped ? rect.minY : view.bounds.maxY - rect.maxY
        let minX = max(0, Int(floor(rect.minX * scaleX)))
        let maxX = min(bitmap.pixelsWide, Int(ceil(rect.maxX * scaleX)))
        let minY = max(0, Int(floor(top * scaleY)))
        let maxY = min(bitmap.pixelsHigh, Int(ceil((top + rect.height) * scaleY)))
        var darkest: CGFloat = 1
        var lightest: CGFloat = 0
        for y in minY..<maxY {
            for x in minX..<maxX {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                darkest = min(darkest, brightness)
                lightest = max(lightest, brightness)
            }
        }
        return lightest - darkest > 0.2
    }
}
