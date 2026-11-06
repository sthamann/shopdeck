import Foundation
import Security

// A separate executable keeps the Keychain client's identity independent of app and MCP builds.
// Credentials travel only through inherited pipes, never command arguments or log messages.
struct Secret:Codable {let clientID:String;let clientSecret:String}
struct Reply:Codable {let status:Int32;let credentials:Secret?}
func finish(_ status:OSStatus,_ credentials:Secret?=nil)->Never {
    if let data=try? JSONEncoder().encode(Reply(status:status,credentials:credentials)){FileHandle.standardOutput.write(data)}
    exit(status == errSecSuccess ? 0:1)
}
let args=CommandLine.arguments
guard args.count==3,let id=UUID(uuidString:args[2]),["load","save","delete","authorize"].contains(args[1]) else{finish(errSecParam)}
let mode=args[1]
SecKeychainSetUserInteractionAllowed(mode=="authorize")
var query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"app.shopdeck.credentials.helper.v2",kSecAttrAccount as String:id.uuidString]
if mode=="load" || mode=="authorize" {
    query[kSecReturnData as String]=true;query[kSecMatchLimit as String]=kSecMatchLimitOne
    var item:CFTypeRef?;let status=SecItemCopyMatching(query as CFDictionary,&item)
    guard status==errSecSuccess,let data=item as? Data,let credentials=try? JSONDecoder().decode(Secret.self,from:data) else{finish(status)}
    finish(status,credentials)
}
if mode=="delete" {let status=SecItemDelete(query as CFDictionary);finish(status==errSecItemNotFound ? errSecSuccess:status)}
let input=FileHandle.standardInput.readDataToEndOfFile()
guard input.count <= 65536,(try? JSONDecoder().decode(Secret.self,from:input)) != nil else{finish(errSecParam)}
let status=SecItemUpdate(query as CFDictionary,[kSecValueData as String:input] as CFDictionary)
if status==errSecItemNotFound {query[kSecValueData as String]=input;query[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;finish(SecItemAdd(query as CFDictionary,nil))}
finish(status)
