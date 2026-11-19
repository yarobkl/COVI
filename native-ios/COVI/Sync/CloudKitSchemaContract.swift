import Foundation

/// The Apple CloudKit Console must contain these record types and one `Bytes`
/// field named `payload` in the `iCloud.com.covi.app` container. Only private
/// database zones are used for the owner's financial and operational records.
enum CloudKitSchemaContract {
    static let container = "iCloud.com.covi.app"
    static let accountIndex = "COVIAccountIndex"
    static let event = "COVIEvent"
    static let operational = "COVIOperationalState"
    static let payloadField = "payload"

    static let recordTypes = [accountIndex, event, operational]
}
