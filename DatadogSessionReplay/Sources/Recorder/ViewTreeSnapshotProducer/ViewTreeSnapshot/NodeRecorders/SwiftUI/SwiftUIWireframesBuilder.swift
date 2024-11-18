/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation
import UIKit

@available(iOS 13.0, *)
internal struct SwiftUIWireframesBuilder: NodeWireframesBuilder {
    internal struct Context {
        var frame: CGRect
        var clip: CGRect
        let builder: WireframesBuilder
    }

    let renderer: DisplayList.ViewUpdater
    /// Text obfuscator for masking text.
    let textObfuscator: TextObfuscating
    /// Flag that determines if font should be scaled
    var fontScalingEnabled: Bool

    let attributes: ViewAttributes

    var wireframeRect: CGRect {
        attributes.frame
    }

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        do {
            let list = try renderer.lastList.reflect()
            let context = Context(
                frame: attributes.frame,
                clip: attributes.clip,
                builder: builder
            )

            return buildWireframes(items: list.items, context: context)
        } catch {
            print(error)
            return []
        }
    }

    private func buildWireframes(items: [DisplayList.Item], context: Context) -> [SRWireframe] {
        items.reduce([]) { wireframes, item in
            switch item.value {
            case let .effect(effect, list):
                return wireframes + effectWireframe(item: item, effect: effect, list: list, context: context)
            case .content(let content):
                return wireframes + contentWireframe(item: item, content: content, context: context)
            case .unknown:
                return wireframes
            }
        }
    }

    private func contentWireframe(item: DisplayList.Item, content: DisplayList.Content, context: Context) -> SRWireframe? {
        let viewInfo = renderer.viewCache.map[.init(id: .init(identity: item.identity))]

        switch content.value {
        case let .shape(_, paint, _):
            return paint.paint.map { paint in
                context.builder.createShapeWireframe(
                    id: Int64(content.seed.value),
                    frame: context.convert(frame: item.frame),
                    clip: context.clip,
                    backgroundColor: CGColor(
                        red: CGFloat(paint.linearRed),
                        green: CGFloat(paint.linearGreen),
                        blue: CGFloat(paint.linearBlue),
                        alpha: CGFloat(paint.opacity)
                    ),
                    cornerRadius: viewInfo?.cornerRadius,
                    opacity: CGFloat(paint.opacity)
                )
            }
        case let .text(view, _):
            let storage = view.text.storage
            let style = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            let foregroundColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
            let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
            return context.builder.createTextWireframe(
                id: Int64(content.seed.value),
                frame: context.convert(frame: item.frame),
                clip: context.clip,
                text: textObfuscator.mask(text: storage.string),
                textAlignment: style.map { .init(systemTextAlignment: $0.alignment) },
                textColor: foregroundColor?.cgColor,
                font: font,
                fontScalingEnabled: fontScalingEnabled
            )
        case .color:
            return context.builder.createShapeWireframe(
                id: Int64(content.seed.value),
                frame: context.convert(frame: item.frame),
                clip: context.clip,
                borderColor: viewInfo?.borderColor,
                borderWidth: viewInfo?.borderWidth,
                backgroundColor: viewInfo?.backgroundColor,
                cornerRadius: viewInfo?.cornerRadius,
                opacity: viewInfo?.alpha
            )
        case .platformView:
            return nil // Should be recorder by UIKit recorder
        case .unknown:
            return nil // Need a placeholder
        }
    }

    private func contentWireframe(item: DisplayList.Item, content: DisplayList.Content, context: Context) -> [SRWireframe] {
        contentWireframe(item: item, content: content, context: context).map { [$0] } ?? []
    }

    func effectWireframe(item: DisplayList.Item, effect: DisplayList.Effect, list: DisplayList, context: Context) -> [SRWireframe] {
        var context = context
        context.frame = context.convert(frame: item.frame)

        switch effect {
        case let .clip(path, style):
            let clip = context.convert(frame: path.boundingRect)
            context.clip = context.clip.intersection(clip)
            return buildWireframes(items: list.items, context: context)

        case .platformGroup:
            return buildWireframes(items: list.items, context: context)

        case .identify, .unknown:
            return buildWireframes(items: list.items, context: context)
        }
    }
}

@available(iOS 13.0, *)
extension SwiftUIWireframesBuilder.Context {
    func convert(frame: CGRect) -> CGRect {
        frame.offsetBy(
            dx: self.frame.origin.x,
            dy: self.frame.origin.y
        )
    }
}

internal func dump<T>(_ value: T, filename: String) throws {
#if canImport(CustomDump)
//    let url = URL.documentsDirectory.appending(path: "hostview.dump")
    let manager = FileManager.default
    let url = manager.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(filename) //swiftlint:disable:this force_unwrapping
    manager.createFile(atPath: url.path, contents: nil, attributes: nil)
    let handle = try FileHandle(forWritingTo: url)
    var stream = FileHandlerOutputStream(handle)
    customDump(value, to: &stream)
    print("Dump:", url)
    handle.closeFile()
#endif
}

#endif
