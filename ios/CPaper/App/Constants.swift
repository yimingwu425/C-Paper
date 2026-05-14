import Foundation

enum Constants {
    static let baseURL = "https://cpaper-api.fly.dev"
    static let dataSourceURL = "https://cie.fraft.cn"
    static let appVersion = "6.0.0"

    static let seasons = ["Mar", "Jun", "Nov"]

    enum API {
        static let subjects = "/obj/Common/Subject/combo"
        static let search = "/obj/Common/Fetch/renum"
        static let download = "/obj/Common/Fetch/redir"
    }
}
