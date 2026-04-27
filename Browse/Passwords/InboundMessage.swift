import Foundation

enum FormClassification: String, Decodable {
    case login, signup, change_password
}

enum FieldRole: String, Decodable {
    case username, password
}

struct CGRectPayload: Decodable {
    let x: Double, y: Double, w: Double, h: Double
    var cgRect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

struct DetectedForm: Decodable {
    let unitId: String
    let classification: FormClassification
    let usernameFieldId: String?
    let passwordFieldId: String
    let usernameRect: CGRectPayload?
    let passwordRect: CGRectPayload
}

enum InboundMessage: Decodable {
    case formsDetected(site: String, forms: [DetectedForm])
    case fieldFocused(unitId: String, fieldId: String, role: FieldRole, rect: CGRectPayload)
    case fieldBlurred(fieldId: String)
    case viewportChanged
    case formSubmitted(unitId: String, classification: FormClassification,
                       username: String, password: String)
    case loginLikelySucceeded(unitId: String)
    case loginInconclusive(unitId: String)
    case scriptReady(site: String)

    private enum Kind: String, Decodable {
        case formsDetected, fieldFocused, fieldBlurred, viewportChanged
        case formSubmitted, loginLikelySucceeded, loginInconclusive, scriptReady
    }

    private enum Keys: String, CodingKey {
        case kind, site, forms, unitId, fieldId, role, rect
        case classification, username, password
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .formsDetected:
            self = .formsDetected(site: try c.decode(String.self, forKey: .site),
                                  forms: try c.decode([DetectedForm].self, forKey: .forms))
        case .fieldFocused:
            self = .fieldFocused(unitId: try c.decode(String.self, forKey: .unitId),
                                 fieldId: try c.decode(String.self, forKey: .fieldId),
                                 role: try c.decode(FieldRole.self, forKey: .role),
                                 rect: try c.decode(CGRectPayload.self, forKey: .rect))
        case .fieldBlurred:
            self = .fieldBlurred(fieldId: try c.decode(String.self, forKey: .fieldId))
        case .viewportChanged:
            self = .viewportChanged
        case .formSubmitted:
            self = .formSubmitted(unitId: try c.decode(String.self, forKey: .unitId),
                                  classification: try c.decode(FormClassification.self, forKey: .classification),
                                  username: try c.decode(String.self, forKey: .username),
                                  password: try c.decode(String.self, forKey: .password))
        case .loginLikelySucceeded:
            self = .loginLikelySucceeded(unitId: try c.decode(String.self, forKey: .unitId))
        case .loginInconclusive:
            self = .loginInconclusive(unitId: try c.decode(String.self, forKey: .unitId))
        case .scriptReady:
            self = .scriptReady(site: try c.decode(String.self, forKey: .site))
        }
    }
}
