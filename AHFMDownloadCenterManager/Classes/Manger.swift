//
//  Manger.swift
//  AHFMDownloadCenter
//
//  Created by Andy Tong on 10/1/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import UIKit
import AHFMDataCenter
import AHFMNetworking
import AHFMDataTransformers
import AHFMDownloadListServices
import AHFMAudioPlayerVCServices
import AHServiceRouter
import AHDownloadTool


class Manager: NSObject {
    lazy var netwroking = AHFMNetworking()
    
    deinit {
        netwroking.cancelAllRequests()
    }
    
}

//MARK:- From downloadedVC and showPage
extension Manager {
    /// Call loadEpisodesForShow(_:) when data is ready
    func downloadedShowPageVC(_ vc: UIViewController, shouldLoadEpisodesForShow showId: Int){
        // NO networking involved since those episodes are supposed to be downloaded alrady.
        let eps = AHFMEpisode.query("showId", "=", showId).run()
        if eps.count > 0 {
            var arrDict = [[String: Any]]()
            for ep in eps {
                let dict = self.merge(ep: ep, epInfo: nil)
                arrDict.append(dict)
            }
            vc.perform(Selector(("loadEpisodesForShow:")), with: arrDict)
        }else{
             vc.perform(Selector(("loadEpisodesForShow:")), with: [])
        }
        
    }
    
    func downloadedVCShowPage(_ vc: UIViewController, didSelectShow showId: Int){
        print("should go to AHFMShowPage")
    }
    
    func downloadedVCShowPage(_ vc: UIViewController, didSelectEpisode episodeId: Int, showId: Int){
        var type: AHServiceNavigationType
        if vc.navigationController != nil {
            type = .push(navVC: vc.navigationController!)
        }else{
            type = .presentWithNavVC(currentVC: vc)
        }
        AHServiceRouter.navigateVC(AHFMAudioPlayerVCServices.service, taskName: AHFMAudioPlayerVCServices.taskNavigation, userInfo: [AHFMAudioPlayerVCServices.keyTrackId: episodeId], type: type, completion: nil)
    }
    
    func downloadedVCShowPage(_ vc: UIViewController, didSelectDownloadMoreForShow showId: Int){
        // go to AHFMDownloadList
        
        var type: AHServiceNavigationType
        if vc.navigationController != nil {
            type = .push(navVC: vc.navigationController!)
        }else{
            type = .presentWithNavVC(currentVC: vc)
        }
        
        let infoDict: [String : Any] = [AHFMDownloadListService.keyShouldShowRightNavBarButton: false, AHFMDownloadListService.keyShowId: showId]
        AHServiceRouter.navigateVC(AHFMDownloadListService.service, taskName: AHFMDownloadListService.taskNavigation, userInfo: infoDict, type: type, completion: nil)
    }
    
    
    func downloadedShowPageVC(_ vc: UIViewController, editingModeDidChange isEditing: Bool){
        print("should show or hide AHFMBottomPlayer")
    }
    
    
    /// Delete downloaded episodes for this showId
    /// You should delete the info in the DB, AND their local actual files
    func downloadedShowPageVC(_ vc: UIViewController, shouldDeleteEpisodes episodeIDs: [Int], forShow showId: Int){
        DispatchQueue.global().async {
            AHFMEpisode.write {
                // Delete files first so that you will still have their localFilePaths
                for epId in episodeIDs {
                    if var epInfo = AHFMEpisodeInfo.query(byPrimaryKey: epId),var show = AHFMShow.query(byPrimaryKey: showId) {
                        show.totalFilesSize -= epInfo.fileSize ?? 0
                        show.hasNewDownload = false
                        show.numberOfEpDownloaded -= 1
                        
                        epInfo.downloadedProgress = 0.0
                        epInfo.unfinishedFilePath = nil
                        epInfo.localFilePath = nil
                        epInfo.isDownloaded = false
                        
                        
                        DispatchQueue.global().async {
                            if let localFilePath = epInfo.localFilePath {
                                AHFileTool.remove(filePath: localFilePath)
                            }
                        }
                        
                        
                        try? AHFMShow.update(model: show)
                        try? AHFMEpisodeInfo.update(model: epInfo)
                    }
                    
                }
            }
        }
        
    }
    
    
    /// Call loadDownloadedShows(_:) when ready
    /// Load all shows with at least one downloaded episode
    func downloadedVCLoadDownloadedShows(_ vc: UIViewController){
        let shows = AHFMShow.query("numberOfEpDownloaded", ">", 0).run()
        var showDict = [[String: Any]]()
        for show in shows {
            let dict = self.transformShowToDict(show: show)
            showDict.append(dict)
        }
        
        vc.perform(Selector(("loadDownloadedShows:")), with: showDict)
    }
    
    /// Delete all downloaded episodes for this showId
    func downloadedVC(_ vc: UIViewController, shouldDeleteShow showId: Int){
        DispatchQueue.global().async {
            AHFMEpisode.write {
                // Delete files first so that you will still have their localFilePaths
                let eps = AHFMEpisode.query("showId", "=", showId).run()
                for ep in eps {
                    if var epInfo = AHFMEpisodeInfo.query(byPrimaryKey: ep.id),var show = AHFMShow.query(byPrimaryKey: showId) {
                        show.totalFilesSize -= epInfo.fileSize ?? 0
                        show.hasNewDownload = false
                        show.numberOfEpDownloaded -= 1
                        
                        epInfo.downloadedProgress = 0.0
                        epInfo.unfinishedFilePath = nil
                        epInfo.localFilePath = nil
                        epInfo.isDownloaded = false
                        
                        
                        DispatchQueue.global().async {
                            if let localFilePath = epInfo.localFilePath {
                                AHFileTool.remove(filePath: localFilePath)
                            }
                        }
                        
                        
                        try? AHFMShow.update(model: show)
                        try? AHFMEpisodeInfo.update(model: epInfo)
                    }
                }
            }
        }
    }
    
    /// You should unmark AHFMShow's hasNewDownload property for the showId
    func downloadedVC(_ vc: UIViewController, willEnterShowPageWithShowId showId: Int){
        AHFMShow.write {
            if var show = AHFMShow.query(byPrimaryKey: showId) {
                show.hasNewDownload = false
                try? AHFMShow.update(model: show)
            }
        }
        
    }
    
    /// Fetch the show that has an episode with that specific remote URL
    /// Call addHasNewDownloaded(_) when the data is ready
    func downloadedVC(_ vc: UIViewController, shouldFetchShowWithEpisodeRemoteURL url: String){
        let eps = AHFMEpisode.query("audioURL", "=", url).run()
        if eps.count > 0 , let ep = eps.first {
            if let show = AHFMShow.query(byPrimaryKey: ep.showId) {
                let showDict = self.transformShowToDict(show: show)
                vc.perform(Selector(("addHasNewDownloaded:")), with: showDict)
                return
            }
        }
        
        vc.perform(Selector(("addHasNewDownloaded:")), with: nil)
    }
}

//MARK:- From downloadingVC
extension Manager {
    /// Call addCurrentDownloads(_:)
    func downloadingVCGetCurrentDownloads(_ vc: UIViewController, urls: [String]){
        // get current download task
        DispatchQueue.global().async {
            let urls = urls
            var currentArrDict = [[String: Any]]()
            for url in urls {
                let eps = AHFMEpisode.query("audioURL", "=", url).run()
                if eps.count > 0, let ep = eps.first {
                    let epInfo = AHFMEpisodeInfo.query(byPrimaryKey: ep.id)
                    let dict = self.merge(ep: ep, epInfo: epInfo)
                    currentArrDict.append(dict)
                }
            }
            DispatchQueue.main.async {
                vc.perform(Selector(("addCurrentDownloads:")), with: currentArrDict)
            }
        }
        
        // get archived download task
        DispatchQueue.global().async {
            let urls = urls
            var archivedArrDict = [[String: Any]]()
            let epInfoArr = AHFMEpisodeInfo.query("downloadedProgress", ">", 0.0).AND("isDownloaded", "=", false).run()
            for epInfo in epInfoArr {
                let eps = AHFMEpisode.query("audioURL", "NOT IN", urls).run()
                if eps.count > 0, let ep = eps.first {
                    let dict = self.merge(ep: ep, epInfo: epInfo)
                    archivedArrDict.append(dict)
                }
            }
            DispatchQueue.main.async {
                vc.perform(Selector(("addArchivedDownloads:")), with: archivedArrDict)
            }
        }
    }
    /// Call addArchivedDownloads(_:)
    func downloadingVCGetArchivedDownloads(_ vc: UIViewController){
        // implemented in downloadingVCGetCurrentDownloads, for convenience.
    }
    
    /// Only help empty out related info in the DB. You don't need to take care of actual unfinished temp files.
    func downloadingVC(_ vc: UIViewController, shouldDeleteEpisodes episodeIDs: [Int], forShow showId: Int){
        AHFMEpisode.write {
            for epId in episodeIDs {
                if var epInfo = AHFMEpisodeInfo.query(byPrimaryKey: epId),var show = AHFMShow.query(byPrimaryKey: showId) {
                    show.totalFilesSize -= epInfo.fileSize ?? 0
                    show.hasNewDownload = false
                    show.numberOfEpDownloaded -= 1
                    
                    epInfo.downloadedProgress = 0.0
                    epInfo.unfinishedFilePath = nil
                    epInfo.localFilePath = nil
                    epInfo.isDownloaded = false
                    
                    try? AHFMShow.update(model: show)
                    try? AHFMEpisodeInfo.update(model: epInfo)
                }
                
            }
        }
    }
}

//MARK:- Data Transform
extension Manager {
    // Show
    //    self.id = dict["id"] as! Int
    //    self.hasNewDownload = dict["hasNewDownload"] as! Bool
    //    self.thumbCover = dict["thumbCover"] as! String
    //    self.title = dict["title"] as! String
    //    self.detail = dict["detail"] as! String
    //    self.numberOfDownloaded = dict["numberOfDownloaded"] as! Int
    //    self.totalDownloadedSize = dict["totalDownloadedSize"] as! Int
    
    func transformShowToDict(show: AHFMShow) -> [String: Any] {
        return [:]
    }
    
    // Episode
    //    self.id = dict["id"] as! Int
    //    self.showId = dict["showId"] as! Int
    //    self.remoteURL = dict["remoteURL"] as! String
    //    self.title = dict["title"] as! String
    //    self.fileSize = dict["fileSize"] as? Int
    //    self.duration = dict["duration"] as? TimeInterval
    //    self.lastPlayedTime = dict["lastPlayedTime"] as? TimeInterval
    //    self.downloadProgress = dict["id"] as? Double
    
    func merge(ep: AHFMEpisode, epInfo: AHFMEpisodeInfo?) -> [String: Any] {
        return [:]
    }
}





