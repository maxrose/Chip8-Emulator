//
//  ViewController.swift
//  Chip8
//
//  Created by Max Rose on 9/8/17.
//  Copyright © 2017 Max Rose. All rights reserved.
//

import Cocoa
import QuartzCore

class EmulatorView: NSView {
    weak var emulator: Emulator?

    var borderColor: NSColor = .darkGray
    var blankColor: NSColor = .black
    var activeColor: NSColor = .lightGray

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let intrinsicSize = self.intrinsicContentSize
        self.widthAnchor.constraint(greaterThanOrEqualToConstant: intrinsicSize.width).isActive = true
        self.heightAnchor.constraint(greaterThanOrEqualToConstant: intrinsicSize.height).isActive = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)

        let intrinsicSize = self.intrinsicContentSize
        self.widthAnchor.constraint(greaterThanOrEqualToConstant: intrinsicSize.width).isActive = true
        self.heightAnchor.constraint(greaterThanOrEqualToConstant: intrinsicSize.height).isActive = true
    }

    var canvas: NSRect {
        let targetRatio = CGFloat(Emulator.pixelWidth / Emulator.pixelHeight)

        let targetSize = NSSize(width: min(self.bounds.width, self.bounds.height * targetRatio), height: min(self.bounds.height, self.bounds.width / targetRatio))

        return self.bounds.insetBy(dx: (self.bounds.size.width - targetSize.width)/2, dy: (self.bounds.size.height - targetSize.height)/2)
    }
    static let smallestPixelSize = 8
    override var intrinsicContentSize: NSSize {
        return NSSize(width: EmulatorView.smallestPixelSize * Emulator.pixelWidth, height: EmulatorView.smallestPixelSize * Emulator.pixelHeight)
    }

    var pixelSize: NSSize {
        return NSSize(width: self.canvas.width / CGFloat(Emulator.pixelWidth), height: self.canvas.height / CGFloat(Emulator.pixelHeight))
    }

    override func draw(_ dirtyRect: NSRect) {
        self.borderColor.set()
        NSRectFill(self.bounds)

        guard let emulator = self.emulator else {
            return
        }
        let canvas = self.canvas
        self.blankColor.set()
        NSRectFill(canvas)

        self.activeColor.set()
        let pixelSize = self.pixelSize
        var pixel = NSRect(origin: .zero, size: pixelSize)
        var onPixels = [NSRect]()
        for i in 0..<emulator.pixelData.count {
            guard emulator.pixelData[i] else {
                continue
            }

            let row = i/Emulator.pixelWidth
            let column = i%Emulator.pixelWidth

            pixel.origin.x = canvas.minX + CGFloat(column) * pixelSize.width
            pixel.origin.y = canvas.maxY - CGFloat(row + 1) * pixelSize.height
            onPixels.append(pixel)
        }

        NSRectFillList(&onPixels, onPixels.count)
    }
}

class ViewController: NSViewController {
    var emulator = Emulator()
    private var emulatorView: EmulatorView! {
        return self.view as! EmulatorView
    }
    var gameTimer: CVDisplayLink?

    override func loadView() {
        self.view = EmulatorView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup emulator
        self.emulatorView.emulator = self.emulator

        // Load content
        let rom = "Maze"
        guard let url = Bundle.main.url(forResource: rom, withExtension: "ch8") else {
            print("Can't find rom \(rom)")
            return
        }

        guard let program = try? Data(contentsOf: url) else {
            print("Can't read rom \(rom)")
            return
        }
        self.emulator.loadProgram(program)
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        // Trigger game loop
        guard self.emulator.hasLoadedProgram else {
            print("No program loaded.")
            return
        }

        let error = CVDisplayLinkCreateWithCGDisplay(CGMainDisplayID(), &self.gameTimer)
        guard let link = self.gameTimer else {
            print("Failed to set up game loop: \(error)")
            return
        }

        CVDisplayLinkSetOutputCallback(link, { (displayLink, inNow, inOutputTime, flagsIn, flagsOut, context) -> CVReturn in
            guard let context = context else {
                return kCVReturnError
            }
            let target = unsafeBitCast(context, to: ViewController.self)
            target.update()
            return kCVReturnSuccess
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))

        CVDisplayLinkStart(link)
    }

    override func viewWillDisappear() {
        if let link = self.gameTimer {
            CVDisplayLinkStop(link)
        }
    }

    func update() {
        // Emulate one cycle
        self.emulator.cycle()

        // Draw
        if self.emulator.needsDraw {
            self.view.needsDisplay = true
            self.view.displayIfNeeded()
        }
        // Read input
        // TBD
    }

    override func keyDown(with event: NSEvent) {
        // event.keyCode
    }

    override func keyUp(with event: NSEvent) {
        // event.keyCode
    }
}

