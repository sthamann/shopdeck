import Foundation
import Darwin
public enum LocalShopSuggestion {
    public static func name(existing:[String],prefix:String)->String {let used=Set(existing.map{$0.lowercased()});if !used.contains(prefix.lowercased()){return prefix};for index in 2...100000{let candidate=prefix+" "+String(index);if !used.contains(candidate.lowercased()){return candidate}};return prefix+" "+UUID().uuidString.prefix(6)}
    public static func available(_ port:Int)->Bool {guard (1024...65535).contains(port)else{return false};let fd=socket(AF_INET,SOCK_STREAM,0);guard fd>=0 else{return false};defer{close(fd)};var address=sockaddr_in();address.sin_len=UInt8(MemoryLayout<sockaddr_in>.size);address.sin_family=sa_family_t(AF_INET);address.sin_port=in_port_t(port).bigEndian;address.sin_addr.s_addr=inet_addr("127.0.0.1");return withUnsafePointer(to:&address){pointer in pointer.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.bind(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size))==0}}}
    public static func port(reserved:Set<Int>,startingAt:Int=8888)->Int?{(max(1024,startingAt)...65535).first{!reserved.contains($0) && available($0)}}
}
