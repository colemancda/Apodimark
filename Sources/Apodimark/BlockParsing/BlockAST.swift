
enum BlockNode <View: BidirectionalCollection> {
    case paragraph(ParagraphNode<View>)
    case header(HeaderNode<View>)
    case quote(QuoteNode<View>)
    case listItem(ListItemNode<View>)
    case list(ListNode<View>)
    case fence(FenceNode<View>)
    case code(CodeNode<View>)
    case thematicBreak(ThematicBreakNode<View>)
    case referenceDefinition(ReferenceDefinitionNode<View>)
}

final class ParagraphNode <View: BidirectionalCollection> {
    var text: [Range<View.Index>]
    var closed: Bool
    init(text: [Range<View.Index>]) {
        (self.text, self.closed) = (text, false)
    }
}

final class HeaderNode <View: BidirectionalCollection> {
    let markers: (Range<View.Index>, Range<View.Index>?)
    let text: Range<View.Index>
    let level: Int32
    
    init(markers: (Range<View.Index>, Range<View.Index>?), text: Range<View.Index>, level: Int32) {
        (self.markers, self.text, self.level) = (markers, text, level)
    }
}

final class QuoteNode <View: BidirectionalCollection> {
    var markers: [View.Index]
    var _allowsLazyContinuation: Bool
    var closed: Bool

    init(firstMarker: View.Index) {
        (self.markers, self.closed, self._allowsLazyContinuation) = ([firstMarker], false, false)
    }
}

final class ListItemNode <View: BidirectionalCollection> {
    let markerSpan: Range<View.Index>
    
    init(markerSpan: Range<View.Index>) {
        self.markerSpan = markerSpan
    }
}

final class ListNode <View: BidirectionalCollection> {
    let kind: ListKind
    var _allowsLazyContinuations: Bool
    
    var state: ListState
    var minimumIndent: Int
    
    init(kind: ListKind, state: ListState) {
        self.kind = kind
        self.state = state
        self.minimumIndent = 0
        self._allowsLazyContinuations = false
    }
}

final class FenceNode <View: BidirectionalCollection> {
    typealias Indices = Range<View.Index>
    
    let kind: FenceKind
    var markers: (Indices, Indices?)
    let name: Indices
    var text: [Indices]
    let level: Int32
    let indent: Int
    var closed: Bool
    
    init(kind: FenceKind, startMarker: Indices, name: Indices, text: [Indices], level: Int32, indent: Int) {
        (self.kind, self.markers, self.name, self.text, self.level, self.indent, self.closed) = (kind, (startMarker, nil), name, text, level, indent, false)
    }
}

final class CodeNode <View: BidirectionalCollection> {
    var text: [Range<View.Index>]
    var trailingEmptyLines: [Range<View.Index>]
    
    init(text: [Range<View.Index>], trailingEmptyLines: [Range<View.Index>]) {
        (self.text, self.trailingEmptyLines) = (text, trailingEmptyLines)
    }
}

final class ThematicBreakNode <View: BidirectionalCollection> {
    let span: Range<View.Index>
    
    init(span: Range<View.Index>) {
        self.span = span
    }
}

final class ReferenceDefinitionNode <View: BidirectionalCollection> {
    let title: String
    let definition: ReferenceDefinition
    
    init(title: String, definition: ReferenceDefinition) {
        (self.title, self.definition) = (title, definition)
    }
}


extension MarkdownParser {
    
    private func strand(line: Line<View>, appendingTo arr: inout [BlockNode<View>]) {
        
        guard line.indent.level < 4 else {
            var newLine = line
            newLine.removeFirstIndents(4)
            restoreIndentInLine(&newLine)
            arr.append(.code(.init(text: [newLine.indices], trailingEmptyLines: [])))
            return
        }
        
        switch line.kind {
        case .quote(let rest):
            arr.append(.quote(.init(firstMarker: line.indices.lowerBound)))
            strand(line: rest, appendingTo: &arr)
        
        case .text:
            arr.append(.paragraph(.init(text: [line.indices])))
        
        case .header(let text, let level):
            let startHashes = line.indices.lowerBound ..< view.index(line.indices.lowerBound, offsetBy: numericCast(level))
            let endHashes: Range<View.Index>? = {
                let tmp = text.upperBound ..< line.indices.upperBound
                return tmp.isEmpty ? nil : tmp
            }()
            arr.append(.header(.init(markers: (startHashes, endHashes), text: text, level: level)))
        
        case let .list(kind, rest):
            let state: ListState = rest.kind.isEmpty() ? .followedByEmptyLine : .normal
            
            let markerSpan = line.indices.lowerBound ..< view.index(line.indices.lowerBound, offsetBy: numericCast(kind.width))
            
            let list = ListNode<View>(kind: kind, state: state)
            let item = ListItemNode<View>(markerSpan: markerSpan)
            
            arr.append(.list(list))
            arr.append(.listItem(item))

            list.minimumIndent = line.indent.level + kind.width + rest.indent.level + 1
            
            guard !rest.kind.isEmpty() else {
                return
            }
            
            let idx = arr.endIndex
            strand(line: rest, appendingTo: &arr)

            if case .code = arr[idx] {
                list.minimumIndent = line.indent.level + kind.width + 1
            }
            
        case let .fence(kind, name, level):
            let startMarker = line.indices.lowerBound ..< view.index(line.indices.lowerBound, offsetBy: numericCast(level))
            arr.append(.fence(.init(kind: kind, startMarker: startMarker, name: name, text: [], level: level, indent: line.indent.level)))

        case .thematicBreak:
            arr.append(.thematicBreak(.init(span: line.indices)))
            
        case .empty:
            arr.append(.paragraph(.init(text: [])))
            
        case let .reference(title, definition):
            arr.append(.referenceDefinition(.init(title: title, definition: definition)))
        }
    }

    func strand(line: Line<View>) -> [BlockNode<View>] {
        var a: [BlockNode<View>] = []
        strand(line: line, appendingTo: &a)
        var childAllowsLazyContinuation: Bool = true
        for x in a.reversed() {
            switch x {
            case .list(let l):
                l._allowsLazyContinuations = childAllowsLazyContinuation
            case .listItem:
                break
            case .quote(let q):
                q._allowsLazyContinuation = childAllowsLazyContinuation
            default:
                childAllowsLazyContinuation = x.allowsLazyContinuation()
            }
        }
        return a
    }
}

