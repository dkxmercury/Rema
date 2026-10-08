import Contacts
import Foundation
import RemaCore

struct BirthdayContact: Identifiable, Equatable {
    let id: String
    let name: String
    let month: Int
    let day: Int
}

// Contacts are read only when the person asks, for birthdays and for the «Call» button of a reminder about someone.
enum ContactsFeed {
    static var authorized: Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        return status == .authorized || status.rawValue == 4
    }

    static func requestAccess() async -> Bool {
        (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
    }

    static func birthdays() -> [BirthdayContact] {
        guard authorized else { return [] }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactBirthdayKey] as [CNKeyDescriptor]
        var found: [BirthdayContact] = []
        try? CNContactStore().enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
            guard let birthday = contact.birthday, let month = birthday.month, let day = birthday.day else { return }
            let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            found.append(BirthdayContact(id: contact.identifier, name: name.isEmpty ? contact.nickname : name, month: month, day: day))
        }
        return found.filter { !$0.name.isEmpty }
    }

    // «Позвонить маме» finds «Мама»: the stem of a title word against first names and nicknames, only in a title about calling or writing.
    static func match(_ title: String) -> ContactLink? {
        guard authorized else { return nil }
        let lowered = title.lowercased()
        guard callWords.contains(where: { lowered.contains($0) }) else { return nil }
        let words = Set(lowered.split(whereSeparator: { !$0.isLetter }).map { stem(String($0)) }.filter { $0.count >= 3 })
        guard !words.isEmpty else { return nil }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        var found: [ContactLink] = []
        try? CNContactStore().enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, stop in
            guard let phone = contact.phoneNumbers.first?.value.stringValue else { return }
            let names = [contact.givenName, contact.nickname].filter { !$0.isEmpty }
            guard names.contains(where: { words.contains(stem($0.lowercased())) }) else { return }
            let full = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            found.append(ContactLink(name: full.isEmpty ? contact.nickname : full, phone: phone))
            if Set(found.map(\.phone)).count > 1 {
                stop.pointee = true
            }
        }
        // Two Sashas would be a guess, so nothing is offered then.
        return Set(found.map(\.phone)).count == 1 ? found.first : nil
    }

    private static let callWords = ["позвон", "звонок", "звонит", "набрат", "напиш", "написат", "поздрав", "подзвон", "дзвон", "зателефон", "call", "ring ", "phone", "text ", "anruf", "ruf ", "appel", "téléphon", "telefon", "телефон", "qo‘ng‘iroq", "qoʻngʻiroq", "qo’ng’iroq", "qo`ng`iroq", "qo'ng'iroq", "qongiroq", "қўнғироқ", "اتصل", "كلم"]

    private static let dismissedKey = "contactsDismissed"

    static func isDismissed(_ id: UUID) -> Bool {
        (UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []).contains(id.uuidString)
    }

    static func dismiss(_ id: UUID) {
        var ids = UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []
        guard !ids.contains(id.uuidString) else { return }
        ids.append(id.uuidString)
        UserDefaults.standard.set(Array(ids.suffix(500)), forKey: dismissedKey)
    }

    private static func stem(_ word: String) -> String {
        for ending in ["ами", "ями", "ой", "ей", "ом", "ем", "ах", "ях", "у", "ю", "а", "я", "е", "ы", "и", "і"] where word.hasSuffix(ending) && word.count - ending.count >= 3 {
            return String(word.dropLast(ending.count))
        }
        return word
    }
}
