//
// Vendored from nicklockwood/SVGPath v1.3.0 (https://github.com/nicklockwood/SVGPath) — MIT License.
// Copied into the SDK (not a package dependency) so it ships via both SwiftPM and CocoaPods with no
// external dependency. Access levels were lowered from `public` to internal to keep these types off
// the SDK's public API surface; otherwise unmodified. See LICENSE.md in this directory.
//

//
//  SVGPath+SwiftUI.swift
//  SVGPath
//
//  Created by Nick Lockwood on 08/01/2025.
//  Copyright © 2025 Nick Lockwood. All rights reserved.
//
//  Distributed under the permissive MIT license
//  Get the latest version from here:
//
//  https://github.com/nicklockwood/SVGPath
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//  IN THE SOFTWARE.
//

#if canImport(SwiftUI)

import SwiftUI

// MARK: SVGPath to SwiftUI Path

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension Path {
    /// Create a SwiftUI `Path` from an SVG path string.
    /// - Parameters:
    ///   - svgPath: The SVG path string.
    ///   - rect: An optional rectangle that the path should be scaled to fit inside.
    init(svgPath: String, in rect: CGRect? = nil) throws {
        try self.init(SVGPath(string: svgPath, with: .init(invertYAxis: false)), in: rect)
    }

    /// Create a SwiftUI `Path` from an `SVGPath` instance.
    /// - Parameters:
    ///   - svgPath: The `SVGPath` instance to convert to a `Path`.
    ///   - rect: An optional rectangle that the path should be scaled to fit inside.
    init(_ svgPath: SVGPath, in rect: CGRect? = nil) {
        self.init(CGPath.from(svgPath, in: rect))
    }
}

// MARK: SwiftUI Path to SVGPath

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SVGPath {
    /// Create an `SVGPath` from a SwiftUI `Path`.
    /// - Parameter path: The SwiftUI `Path` to convert.
    init(_ path: Path) {
        self.init(path.cgPath)
    }
}

#endif
