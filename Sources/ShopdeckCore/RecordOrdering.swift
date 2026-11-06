import Foundation
public enum RecordOrdering {
    /// Sort indices, so all values, selection and details keep their shared record identity.
    public static func indices(rows:[JSONValue],shops:[String],ids:[String],descriptors:[(String,Bool)])->[Int] {
        guard !descriptors.isEmpty else{return Array(rows.indices)}
        return rows.indices.sorted { a,b in
            for (field,ascending) in descriptors {
                let left=field=="shop" ? JSONValue.string(shops[a]):rows[a].at(field),right=field=="shop" ? JSONValue.string(shops[b]):rows[b].at(field)
                if left == .null || right == .null {if left != right{return ascending ? left == .null:right == .null};continue}
                let comparison:ComparisonResult
                if let l=left.number,let r=right.number {comparison=l<r ? .orderedAscending:l>r ? .orderedDescending:.orderedSame}
                else if let l=left.bool,let r=right.bool{comparison=l==r ? .orderedSame:l ? .orderedDescending:.orderedAscending}
                else {comparison=left.displayString.compare(right.displayString,options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX"))}
                if comparison != .orderedSame{return ascending ? comparison == .orderedAscending:comparison == .orderedDescending}
            }
            return ids[a]<ids[b]
        }
    }
}
