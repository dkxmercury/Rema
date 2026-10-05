import Foundation

struct HomeContent {
    struct Row: Identifiable {
        let id: Int
        let time: String
        let title: String
        let subtitle: String?
        let done: Bool
        let highlighted: Bool
    }

    struct Tile: Identifiable {
        enum Icon {
            case place
            case yearly
        }

        let id: Int
        let icon: Icon
        let label: String
        let title: String
        let subtitle: String
    }

    let dateLine: String
    let nowHour: Int
    let nowMinute: Int
    let markers: [DialMarker]
    let nextTime: String
    let nextCountdown: String
    let nextTitle: String
    let nextNote: String
    let nextUrgent: Bool
    let rows: [Row]
    let tiles: [Tile]
}

extension HomeContent {
    static let sample = HomeContent(
        dateLine: "Понедельник, 5 октября",
        nowHour: 13,
        nowMinute: 50,
        markers: [
            DialMarker(id: 0, hour: 9, minute: 0, kind: .done),
            DialMarker(id: 1, hour: 14, minute: 30, kind: .next),
            DialMarker(id: 2, hour: 19, minute: 0, kind: .upcoming),
            DialMarker(id: 3, hour: 21, minute: 30, kind: .upcoming),
        ],
        nextTime: "14:30",
        nextCountdown: "через 40 мин",
        nextTitle: "Позвонить поставщику",
        nextNote: "напомню ещё за 15 минут",
        nextUrgent: true,
        rows: [
            Row(id: 0, time: "09:00", title: "Выпить витамины", subtitle: "каждый день · настойчиво", done: true, highlighted: false),
            Row(id: 1, time: "14:30", title: "Позвонить поставщику", subtitle: "срочно · за 15 минут", done: false, highlighted: true),
            Row(id: 2, time: "19:00", title: "Купить хлеб и молоко", subtitle: nil, done: false, highlighted: false),
            Row(id: 3, time: "21:30", title: "Полить цветы", subtitle: "пн и чт", done: false, highlighted: false),
        ],
        tiles: [
            Tile(id: 0, icon: .place, label: "По месту", title: "Забрать посылку", subtitle: "уйду: работа, спортзал"),
            Tile(id: 1, icon: .yearly, label: "Каждый год", title: "Оплатить сервер", subtitle: "завтра в 10:00"),
        ]
    )
}
