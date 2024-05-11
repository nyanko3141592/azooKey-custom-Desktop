//
//  InputState.swift
//  azooKeyMac
//
//  Created by 高橋直希 on 2024/05/11.
//
import Foundation
import Cocoa

enum InputState {
    case none
    case composing
    case selecting(rangeAdjusted: Bool)

    mutating func handleNoneState(_ userAction: UserAction, _ event: NSEvent) -> ClientAction {
        switch userAction {
        case .input(let string):
            self = .composing
            return .appendToMarkedText(string)
        case .かな:
            return .selectInputMode(.japanese)
        case .英数:
            return .selectInputMode(.roman)
        case .unknown, .navigation, .space, .delete, .enter:
            return .fallthrough
        }
    }

    mutating func handleComposingState(_ userAction: UserAction, _ event: NSEvent) -> ClientAction {
        switch userAction {
        case .input(let string):
            return .appendToMarkedText(string)
        case .delete:
            return .removeLastMarkedText
        case .enter:
            self = .none
            return .commitMarkedText
        case .space:
            self = .selecting(rangeAdjusted: false)
            return .showCandidateWindow
        case .かな:
            return .selectInputMode(.japanese)
        case .英数:
            self = .none
            return .sequence([.commitMarkedText, .selectInputMode(.roman)])
        case .navigation(let direction):
            if direction == .down {
                self = .selecting(rangeAdjusted: false)
                return .showCandidateWindow
            } else if direction == .right && event.modifierFlags.contains(NSEvent.ModifierFlags.shift) {
                self = .selecting(rangeAdjusted: true)
                return .sequence([.moveCursorToStart, .moveCursor(1), .showCandidateWindow])
            } else if direction == .left && event.modifierFlags.contains(NSEvent.ModifierFlags.shift) {
                self = .selecting(rangeAdjusted: true)
                return .sequence([.moveCursor(-1), .showCandidateWindow])
            } else {
                return .consume
            }
        case .unknown:
            return .fallthrough
        }
    }

    mutating func handleSelectingState(_ userAction: UserAction, _ event: NSEvent, _ rangeAdjusted: Bool) -> ClientAction {
        switch userAction {
        case .input(let string):
            self = .composing
            return .sequence([.submitSelectedCandidate, .appendToMarkedText(string)])
        case .enter:
            self = .none
            return .submitSelectedCandidate
        case .delete:
            self = .composing
            return .removeLastMarkedText
        case .space:
            let (keyCode, characters) =
                if event.modifierFlags.contains(NSEvent.ModifierFlags.shift) {
                    (126 as UInt16, "\u{F700}")
                } else {
                    (125 as UInt16, "\u{F701}")
                }
            return .forwardToCandidateWindow(
                .keyEvent(
                    with: .keyDown,
                    location: event.locationInWindow,
                    modifierFlags: event.modifierFlags.subtracting(NSEvent.ModifierFlags.shift),
                    timestamp: event.timestamp,
                    windowNumber: event.windowNumber,
                    context: nil,
                    characters: characters,
                    charactersIgnoringModifiers: characters,
                    isARepeat: event.isARepeat,
                    keyCode: keyCode
                ) ?? event
            )
        case .navigation(let direction):
            if direction == .right {
                if event.modifierFlags.contains(NSEvent.ModifierFlags.shift) {
                    if rangeAdjusted {
                        return .sequence([.moveCursor(1), .showCandidateWindow])
                    } else {
                        self = .selecting(rangeAdjusted: true)
                        return .sequence([
                            .moveCursorToStart, .moveCursor(1), .showCandidateWindow,
                        ])
                    }
                } else {
                    return .submitSelectedCandidate
                }
            } else if direction == .left && event.modifierFlags.contains(NSEvent.ModifierFlags.shift) {
                self = .selecting(rangeAdjusted: true)
                return .sequence([.moveCursor(-1), .showCandidateWindow])
            } else {
                return .forwardToCandidateWindow(event)
            }
        case .かな:
            return .selectInputMode(.japanese)
        case .英数:
            self = .none
            return .sequence([.submitSelectedCandidate, .selectInputMode(.roman)])
        case .unknown:
            return .fallthrough
        }
    }

    mutating func event(_ event: NSEvent!, userAction: UserAction) -> ClientAction {
        if event.modifierFlags.contains(NSEvent.ModifierFlags.command) {
            return .fallthrough
        }
        if event.modifierFlags.contains(NSEvent.ModifierFlags.option) {
            guard case .input = userAction else {
                return .fallthrough
            }
        }
        switch self {
        case .none:
            return handleNoneState(userAction, event)
        case .composing:
            return handleComposingState(userAction, event)
        case .selecting(let rangeAdjusted):
            return handleSelectingState(userAction, event, rangeAdjusted)
        }
    }
}
