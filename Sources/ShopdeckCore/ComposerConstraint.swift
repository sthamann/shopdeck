import Foundation
public enum ComposerConstraint {
    /// Conservative support for stable Composer constraints. Unsupported expressions do not permit installation.
    public static func matches(_ version:String,requirement:String)->Bool {
        func numbers(_ text:String)->[Int]?{let pieces=text.split(separator:".");guard !pieces.isEmpty,pieces.count<=4,pieces.allSatisfy({Int($0) != nil})else{return nil};return pieces.map{Int($0)!}+Array(repeating:0,count:4-pieces.count)}
        guard let current=numbers(version)else{return false}
        func compare(_ a:[Int],_ b:[Int])->Int{for (left,right) in zip(a,b){if left != right{return left<right ? -1:1}};return 0}
        func clause(_ raw:String)->Bool {
            let clean=raw.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:",",with:" ")
            if clean=="*"{return true}
            let tokens=clean.split(whereSeparator:{$0.isWhitespace}).map(String.init);guard !tokens.isEmpty else{return false}
            return tokens.allSatisfy{token in
                let operators=[">=","<=",">","<","^","~","==","="]
                let op=operators.first{token.hasPrefix($0)} ?? "="
                let value=operators.contains(op) && token.hasPrefix(op) ? String(token.dropFirst(op.count)):token
                if value.contains("*") || value.lowercased().contains("x"){
                    guard op=="=" else{return false};let parts=value.split(separator:".");for (index,part) in parts.enumerated(){if part=="*" || part.lowercased()=="x"{return true};guard index<4,Int(part)==current[index]else{return false}};return true
                }
                guard let bound=numbers(value)else{return false};let c=compare(current,bound)
                switch op{case ">=":return c>=0;case "<=":return c<=0;case ">":return c>0;case "<":return c<0
                case "^","~":var upper=bound;let count=value.split(separator:".").count;let index:Int;if op=="~"{index=count>=3 ? 1:0}else{index=bound[0]>0 ? 0:bound[1]>0 ? 1:2};upper[index]+=1;for i in index+1..<4{upper[i]=0};return c>=0 && compare(current,upper)<0
                default:return c==0}
            }
        }
        return requirement.components(separatedBy:"||").contains(where:clause)
    }
}
