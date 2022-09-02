//
//  DashboardData.swift
//  Widget
//
//  Created by Marino Faggiana on 20/08/22.
//  Copyright © 2022 Marino Faggiana. All rights reserved.
//
//  Author Marino Faggiana <marino.faggiana@nextcloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import WidgetKit
import NextcloudKit

struct DashboardData: Identifiable, Codable, Hashable {
    var id: Int
    var image: String
    var title: String
    var subTitle: String
    var url: URL
}

struct DashboardDataEntry: TimelineEntry {
    let date: Date
    let dashboardDatas: [DashboardData]
    let isPlaceholder: Bool
    let title: String
    let footerText: String
}

let dashboardDatasTest: [DashboardData] = [
    .init(id: 0, image: "nextcloud", title: "title 1", subTitle: "subTitle - description 1", url: URL(string: "https://nextcloud.com/")!),
    .init(id: 1, image: "nextcloud", title: "title 2", subTitle: "subTitle - description 2", url: URL(string: "https://nextcloud.com/")!),
    .init(id: 2, image: "nextcloud", title: "title 3", subTitle: "subTitle - description 3", url: URL(string: "https://nextcloud.com/")!),
    .init(id: 3, image: "nextcloud", title: "title 4", subTitle: "subTitle - description 4", url: URL(string: "https://nextcloud.com/")!),
    .init(id: 4, image: "nextcloud", title: "title 5", subTitle: "subTitle - description 5", url: URL(string: "https://nextcloud.com/")!)
]

func getTitle(account: tableAccount?) -> String {

    let hour = Calendar.current.component(.hour, from: Date())
    var good = ""

    switch hour {
    case 6..<12: good = NSLocalizedString("_good_morning_", value: "Good morning", comment: "")
    case 12: good = NSLocalizedString("_good_noon_", value: "Good noon", comment: "")
    case 13..<17: good = NSLocalizedString("_good_afternoon_", value: "Good afternoon", comment: "")
    case 17..<22: good = NSLocalizedString("_good_evening_", value: "Good evening", comment: "")
    default: good = NSLocalizedString("_good_night_", value: "Good night", comment: "")
    }

    if let account = account {
        return good + ", " + account.displayName
    } else {
        return good
    }
}

func readDashboardData(completion: @escaping (_ dashboardData: [DashboardData], _ isPlaceholder: Bool, _ title: String, _ footerText: String) -> Void) {

    guard let account = NCManageDatabase.shared.getActiveAccount() else {
        return completion(dashboardDatasTest, true, getTitle(account: nil), NSLocalizedString("_no_active_account_", value: "No account found", comment: ""))
    }

    completion(dashboardDatasTest, false, getTitle(account: account), "\(Date().formatted())")
}
