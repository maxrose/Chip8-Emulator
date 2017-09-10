//
//  Chip8.swift
//  Chip8
//
//  Created by Max Rose on 9/8/17.
//  Copyright © 2017 Max Rose. All rights reserved.
//

import Foundation
import Cocoa // For beep

// Emulator based on spec here: https://en.wikipedia.org/wiki/CHIP-8

// Technically UInt16 is needed, but for easier conversion to array indecies, we'll use Int
typealias Opcode = Int
typealias MemoryType = UInt8
typealias Address = Int

extension Int {
    static let indexAndCounterMax: Int = 0xFFF

    // Working with hex values
    static let p1: Opcode = 0xF << 12
    static let p2: Opcode = 0xF << 8
    static let p3: Opcode = 0xF << 4
    static let p4: Opcode = 0xF << 0

    // Opcodes
    static let clearScreen: Opcode = 0x0
    static let returnFromSubroutine: Opcode = 0xE
    static let gotoAddress: Opcode = 0x1
    static let callSubroutine: Opcode = 0x2

    static let skipEqual: Opcode = 0x3
    static let skipNotEqual: Opcode = 0x4
    static let skipEqualRegisters: Opcode = 0x5

    static let setConstant: Opcode = 0x6
    static let addConstant: Opcode = 0x7

    static let variableMath: Opcode = 0x8
    static let assign: Opcode = 0x0
    static let bitOr: Opcode = 0x1
    static let bitAnd: Opcode = 0x2
    static let bitXor: Opcode = 0x3
    static let add: Opcode = 0x4
    static let subtract: Opcode = 0x5
    static let shiftRight: Opcode = 0x6
    static let addNegative: Opcode = 0x7
    static let shiftLeft: Opcode = 0xE

    static let skipNotEqualRegisters: Opcode = 0x9

    static let setIndexRegister: Opcode = 0xA
    static let jumpAhead: Opcode = 0xB

    static let random: Opcode = 0xC

    static let drawSprite: Opcode = 0xD

    static let keyCheck: Opcode = 0xE
    static let skipPressed: (p3: Opcode, p4: Opcode) = (0x9, 0xE)
    static let skipNotPressed: (p3: Opcode, p4: Opcode) = (0xA, 0x1)

    static let saveDelayTimerP3: Opcode = 0x0
    static let saveDelayTimerP4: Opcode = 0x7

    static let awaitKeyP3: Opcode = 0x0
    static let awaitKeyP4: Opcode = 0xA

    static let setTimer: Opcode = 0x1
    static let setDelayTimer: Opcode = 0x5
    static let setSoundTimer: Opcode = 0x8

    static let increaseIndexRegister: (p3: Opcode, p4: Opcode) = (0x1, 0xE)
    static let setFontIndexRegister: (p3: Opcode, p4: Opcode) = (0x2, 0x9)

    static let storeDecimalRepresentation: (p3: Opcode, p4: Opcode) = (0x3, 0x3)

    static let registerDump: (p3: Opcode, p4: Opcode) = (0x5, 0x5)
    static let registerLoad: (p3: Opcode, p4: Opcode) = (0x6, 0x5)
}

// Chip 8 Emulator
// Memory map:
//  0x000-0x1FF - Chip 8 interpreter (contains font set in emu)
//  0x050-0x0A0 - Used for the built in 4x5 pixel font set (0-F)
//  0x200-0xFFF - Program ROM and work RAM
final class Emulator {
    var hasLoadedProgram: Bool {
        return (Opcode(memory[Emulator.programCounterStart]) << 8) | Opcode(memory[Emulator.programCounterStart + 1]) != 0
    }

    static let memoryCapacity: Int = 4096
    static let reservedSpace: Int = 352
    private(set) var memory = [MemoryType](repeating:0, count: memoryCapacity)
    static let registerCount: Int = 16
    private(set) var registers = [MemoryType](repeating:0, count: registerCount)
    private var V: [MemoryType] {
        get { return self.registers }
        set { self.registers = newValue }
    }

    private(set) var indexRegister: Address = 0 {
        didSet {
            if self.indexRegister > .indexAndCounterMax {
                print("Index register went beyond maximum value (\(String(self.indexRegister, radix: 16)) vs \(String(Int.indexAndCounterMax, radix: 16)))")
            }
        }
    }
    private var I: Address {
        get { return self.indexRegister }
        set { self.indexRegister = newValue }
    }

    static let programCounterStart: Address = 0x200
    private(set) var programCounter: Address = programCounterStart {
        didSet {
            if self.programCounter > .indexAndCounterMax {
                print("Program counter went beyond maximum value (\(String(self.indexRegister, radix: 16)) vs \(String(Int.indexAndCounterMax, radix: 16)))")
            }
        }
    }
    private var pc: Address {
        get { return self.programCounter }
        set { self.programCounter = newValue }
    }

    static let stackDepth: Int = 16
    private var stack = [Address](repeating: 0, count: stackDepth)
    private var stackPointer: Address = 0
    private var sp: Address {
        get { return self.stackPointer }
        set { self.stackPointer = newValue }
    }

    static let pixelWidth = 64
    static let pixelHeight = 32
    static let spriteWidth: Int = 8 // 8 bits
    private(set) lazy var pixelData: [Bool] =  [Bool](repeating: false, count: pixelWidth * pixelHeight)
    private var gfx: [Bool] {
        get { return self.pixelData }
        set { self.pixelData = newValue }
    }
    var needsDraw = true

    private(set) var delayTimer: MemoryType = 0
    private(set) var soundTimer: MemoryType = 0

    struct InputKey: OptionSet, CustomStringConvertible {
        let rawValue: UInt16

        // 1, 2, 3, C
        // 4, 5, 6, D
        // 7, 8, 9, E
        // A, 0, B, F
        static let _0 = InputKey(rawValue: 0b1 << 0x0)
        static let _1 = InputKey(rawValue: 0b1 << 0x1)
        static let _2 = InputKey(rawValue: 0b1 << 0x2)
        static let _3 = InputKey(rawValue: 0b1 << 0x3)
        static let _4 = InputKey(rawValue: 0b1 << 0x4)
        static let _5 = InputKey(rawValue: 0b1 << 0x5)
        static let _6 = InputKey(rawValue: 0b1 << 0x6)
        static let _7 = InputKey(rawValue: 0b1 << 0x7)
        static let _8 = InputKey(rawValue: 0b1 << 0x8)
        static let _9 = InputKey(rawValue: 0b1 << 0x9)
        static let A  = InputKey(rawValue: 0b1 << 0xA)
        static let B  = InputKey(rawValue: 0b1 << 0xB)
        static let C  = InputKey(rawValue: 0b1 << 0xC)
        static let D  = InputKey(rawValue: 0b1 << 0xD)
        static let E  = InputKey(rawValue: 0b1 << 0xE)
        static let F  = InputKey(rawValue: 0b1 << 0xF)

        static let none: InputKey = []

        static func readStoredValue(_ value: MemoryType) -> InputKey {
            switch value {
            case 0x0: return ._0
            case 0x1: return ._1
            case 0x2: return ._2
            case 0x3: return ._3
            case 0x4: return ._4
            case 0x5: return ._5
            case 0x6: return ._6
            case 0x7: return ._7
            case 0x8: return ._8
            case 0x9: return ._9
            case 0xA: return .A
            case 0xB: return .B
            case 0xC: return .C
            case 0xD: return .D
            case 0xE: return .E
            case 0xF: return .F
            default: fatalError("Chip 8 has no input corresponding to \(value)")
            }
        }
        fileprivate var storedValue: MemoryType {
            switch self {
            case InputKey._0: return 0x0
            case InputKey._1: return 0x1
            case InputKey._2: return 0x2
            case InputKey._3: return 0x3
            case InputKey._4: return 0x4
            case InputKey._5: return 0x5
            case InputKey._6: return 0x6
            case InputKey._7: return 0x7
            case InputKey._8: return 0x8
            case InputKey._9: return 0x9
            case InputKey.A: return 0xA
            case InputKey.B: return 0xB
            case InputKey.C: return 0xC
            case InputKey.D: return 0xD
            case InputKey.E: return 0xE
            case InputKey.F: return 0xF
            default: fatalError("Attempted to store a multikey press into a single key press register.")
            }
        }

        var description: String{
            var description = ""
            if self.contains(._0) { description += "0" }
            if self.contains(._1) { description += "1" }
            if self.contains(._2) { description += "2" }
            if self.contains(._3) { description += "3" }
            if self.contains(._4) { description += "4" }
            if self.contains(._5) { description += "5" }
            if self.contains(._6) { description += "6" }
            if self.contains(._7) { description += "7" }
            if self.contains(._8) { description += "8" }
            if self.contains(._9) { description += "9" }
            if self.contains(.A)  { description += "A" }
            if self.contains(.B)  { description += "B" }
            if self.contains(.C)  { description += "C" }
            if self.contains(.D)  { description += "D" }
            if self.contains(.E)  { description += "E" }
            if self.contains(.F)  { description += "F" }
            return description
        }
    }
    func pressKey(_ key: InputKey) { self.keys = key }
    func unpressKey(_ key: InputKey) { self.keys.remove(key) }
    private var keys: InputKey = .none

    static let fontCharacterStepSize = 5
    static let fontSet: [MemoryType] = [
        0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
        0x20, 0x60, 0x20, 0x20, 0x70, // 1
        0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
        0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
        0x90, 0x90, 0xF0, 0x10, 0x10, // 4
        0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
        0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
        0xF0, 0x10, 0x20, 0x40, 0x40, // 7
        0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
        0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
        0xF0, 0x90, 0xF0, 0x90, 0x90, // A
        0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
        0xF0, 0x80, 0x80, 0x80, 0xF0, // C
        0xE0, 0x90, 0x90, 0x90, 0xE0, // D
        0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
        0xF0, 0x80, 0xF0, 0x80, 0x80  // F
    ]

    func reset() {
        self.memory = [MemoryType](repeating:0, count: Emulator.memoryCapacity)
        self.pc = Emulator.programCounterStart

        self.registers = [MemoryType](repeating:0, count: Emulator.registerCount)
        self.I = 0

        self.stack = [Address](repeating: 0, count: Emulator.stackDepth)
        self.sp = 0

        self.pixelData = [Bool](repeating: false, count: Emulator.pixelWidth * Emulator.pixelHeight)
        self.needsDraw = true

        // Load fonset
        for i in 0..<Emulator.fontSet.count {
            self.memory[i] = Emulator.fontSet[i]
        }

        self.delayTimer = 0
        self.soundTimer = 0
    }

    func loadProgram(_ program: Data) {
        self.reset()
        let contents = [MemoryType](program)

        guard contents.count <= Emulator.memoryCapacity - Emulator.programCounterStart - Emulator.reservedSpace else {
            print("Rom too large.")
            return
        }

        self.memory.replaceSubrange(Emulator.programCounterStart..<Emulator.programCounterStart + contents.count, with: contents)
    }

    var currentOperation: Opcode {
        return (Opcode(memory[pc]) << 8) | Opcode(memory[self.pc + 1])
    }
    static let operationStepSize: Int = 2

    func cycle() {
        // Fetch Opcode
        let opcode: Opcode = currentOperation

        // Decode Opcode
        var incrementProgramCounter = true
        let p1 = opcode & .p1
        let p2 = opcode & .p2
        let p3 = opcode & .p3
        let p4 = opcode & .p4

        let hexDigits = (p1: p1 >> 12,
                         p2: p2 >> 8,
                         p3: p3 >> 4,
                         p4: p4)
        switch hexDigits {
        case (0, _, 0xE, Opcode.clearScreen):
            pixelData = [Bool](repeating: false, count: Emulator.pixelWidth * Emulator.pixelHeight)
            self.needsDraw = true

        case (0, _, 0xE, Opcode.returnFromSubroutine):
            sp -= 1
            pc = stack[sp]

        case (Opcode.gotoAddress, _, _, _):
            pc = Address(p2 | p3 | p4)
            incrementProgramCounter = false

        case (Opcode.callSubroutine, _, _, _):
            stack[sp] = pc
            sp += 1
            pc = Address(p2 | p3 | p4)
            incrementProgramCounter = false

        case (Opcode.skipEqual, let x, _, _):
            if V[x] == MemoryType(p3 | p4) {
                pc += Emulator.operationStepSize
            }

        case (Opcode.skipNotEqual, let x, _, _):
            if V[x] != MemoryType(p3 | p4) {
                pc += Emulator.operationStepSize
            }

        case (Opcode.skipEqualRegisters, let x, let y, 0):
            if V[x] == V[y] {
                pc += Emulator.operationStepSize
            }

        case (Opcode.setConstant, let x, _, _):
            V[x] = MemoryType(p3 | p4)

        case (Opcode.addConstant, let x, _, _):
            let (value, _) = MemoryType.addWithOverflow(V[x], MemoryType(p3 | p4))
            V[x] = value

        case (Opcode.variableMath, let x, let y, let operation):
            switch operation {
            case Opcode.assign:
                V[x] = V[y]
            case Opcode.bitOr:
                V[x] |= V[y]
            case Opcode.bitAnd:
                V[x] &= V[y]
            case Opcode.bitXor:
                V[x] ^= V[y]
            case Opcode.add:
                let (value, overflow) = MemoryType.addWithOverflow(V[x], V[y])
                V[0xF] = overflow ? 1 : 0
                V[x] = value
            case Opcode.subtract:
                let (value, overflow) = MemoryType.subtractWithOverflow(V[x], V[y])
                V[0xF] = overflow ? 0 : 1
                V[x] = value
            case Opcode.shiftRight:
                V[0xF] = V[x] & 0xF
                V[x] >>= 1
            case Opcode.addNegative:
                // Track overflow
                let (value, overflow) = MemoryType.subtractWithOverflow(V[y], V[x])
                V[0xF] = overflow ? 0 : 1
                V[x] = value
            case Opcode.shiftLeft:
                V[0xF] = V[x] >> 7
                V[x] <<= 1

            default:
                print("unknown opcode [0x8xyN] (varyable math): 0x\(String(hexDigits.p1, radix: 16))\(String(hexDigits.p2, radix: 16))\(String(hexDigits.p3, radix: 16))\(String(hexDigits.p4, radix: 16))")
            }

        case (Opcode.skipNotEqualRegisters, let x, let y, 0):
            if V[x] != V[y] {
                pc += Emulator.operationStepSize
            }

        case (Opcode.setIndexRegister, _, _, _):
            I = Address(p2 | p3 | p4)

        case (Opcode.jumpAhead, _, _, _):
            pc = Address(V[0]) + Address(p2 | p3 | p4)
            incrementProgramCounter = false

        case (Opcode.random, let x, _, _):
            V[x] = MemoryType(arc4random_uniform(UInt32(p3 | p4) + 1))

        case (Opcode.drawSprite, let x, let y, let height):
            let xLocation = Int(V[x])
            let yLocation = Int(V[y])
            V[0xF] = 0 // Set collision to false
            for ySprite in 0..<height {
                let spriteInfo = memory[I + ySprite]
                guard yLocation + ySprite < Emulator.pixelHeight else {
                    continue
                }
                let yIndex = (yLocation + ySprite) * Emulator.pixelWidth
                for xSprite in 0..<Emulator.spriteWidth {
                    let xIndex = xLocation + ( Emulator.spriteWidth - 1 - xSprite)
                    guard yLocation + ySprite < Emulator.pixelHeight || xIndex < Emulator.pixelWidth else {
                        continue
                    }
                    // Guard on sprite displaying pixel
                    guard spriteInfo >> MemoryType(xSprite) & 0b1 == 0b1 else {
                        continue
                    }

                    let graphicsIndex = xIndex + yIndex
                    if gfx[graphicsIndex] {
                        V[0xF] = 1 // Record collision
                    }
                    gfx[graphicsIndex] = !gfx[graphicsIndex]
                }
            }
            needsDraw = true

        case (Opcode.keyCheck, let x, Opcode.skipPressed.p3, Opcode.skipPressed.p4):
            if keys.contains(InputKey.readStoredValue(V[x])) {
                pc += Emulator.operationStepSize
            }

        case (Opcode.keyCheck, let x, Opcode.skipNotPressed.p3, Opcode.skipNotPressed.p4):
            if !keys.contains(InputKey.readStoredValue(V[x])) {
                pc += Emulator.operationStepSize
            }

        case (0xF, let x, Opcode.saveDelayTimerP3, Opcode.saveDelayTimerP4):
            V[x] = delayTimer

        case (0xF, let x, Opcode.awaitKeyP3, Opcode.awaitKeyP4):
            guard keys != .none else {
                // Blocking
                return
            }
            V[x] = keys.storedValue

        case (0xF, let x, Opcode.setTimer, Opcode.setDelayTimer):
            delayTimer = V[x]

        case (0xF, let x, Opcode.setTimer, Opcode.setSoundTimer):
            soundTimer = V[x]

        case (0xF, let x, Opcode.increaseIndexRegister.p3, Opcode.increaseIndexRegister.p4):
            I += Address(V[x])

        case (0xF, let x, Opcode.setFontIndexRegister.p3, Opcode.setFontIndexRegister.p4):
            // Fonts are stored at the begining of memory
            I = Address(V[x]) * Emulator.fontCharacterStepSize

        case (0xF, let x, Opcode.storeDecimalRepresentation.p3, Opcode.storeDecimalRepresentation.p4):
            memory[I]   = V[x] / 100
            memory[I+1] = (V[x] / 10) % 10
            memory[I+2] = V[x] % 10

        case (0xF, let x, Opcode.registerDump.p3, Opcode.registerDump.p4):
            for i in 0...x {
                memory[I + i] = V[i]
            }

        case (0xF, let x, Opcode.registerLoad.p3, Opcode.registerLoad.p4):
            for i in 0...x {
                V[i] = memory[I + i]
            }

        default:
            print("unknown opcode: 0x\(String(hexDigits.p1, radix: 16))\(String(hexDigits.p2, radix: 16))\(String(hexDigits.p3, radix: 16))\(String(hexDigits.p4, radix: 16))")
        }
        if incrementProgramCounter {
            pc += Emulator.operationStepSize
        }

        // Update timers
        if delayTimer > 0 {
            delayTimer -= 1
        }
        if soundTimer > 0 {
            NSBeep()
            soundTimer -= 1
        }
    }
}
