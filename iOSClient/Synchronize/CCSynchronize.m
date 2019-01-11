//
//  CCSynchronize.m
//  Nextcloud iOS
//
//  Created by Marino Faggiana on 19/10/16.
//  Copyright (c) 2017 Marino Faggiana. All rights reserved.
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

#import "CCSynchronize.h"
#import "AppDelegate.h"
#import "CCMain.h"
#import "NCBridgeSwift.h"

@interface CCSynchronize () 
{
    AppDelegate *appDelegate;
}
@end

@implementation CCSynchronize

+ (CCSynchronize *)sharedSynchronize {
    
    static CCSynchronize *sharedSynchronize;
    
    @synchronized(self)
    {
        if (!sharedSynchronize) {
            
            sharedSynchronize = [CCSynchronize new];
            sharedSynchronize.foldersInSynchronized = [NSMutableOrderedSet new];
            sharedSynchronize->appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
        }
        return sharedSynchronize;
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Read Folder =====
#pragma --------------------------------------------------------------------------------------------

// serverUrl    : start
// selector     : selectorReadFolder, selectorReadFolderWithDownload
//

- (void)readFolder:(NSString *)serverUrl selector:(NSString *)selector
{
    [[OCnetworking sharedManager] readFolderWithAccount:appDelegate.activeAccount serverUrl:serverUrl depth:@"1" completion:^(NSString *account, NSArray *metadatas, tableMetadata *metadataFolder, NSString *message, NSInteger errorCode) {
        
        if (errorCode == 0 && [account isEqualToString:appDelegate.activeAccount]) {
            
            tableAccount *tableAccount = [[NCManageDatabase sharedInstance] getAccountWithPredicate:[NSPredicate predicateWithFormat:@"account == %@", account]];
            if (tableAccount == nil) {
                return;
            }
            
            // Add/update self Folder
            if (!metadataFolder || !metadatas || [metadatas count] == 0) {
                if (metadataFolder.serverUrl != nil) {
                    [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:metadataFolder.serverUrl fileID:nil action:k_action_NULL];
                }
                return;
            }
            
            // Add metadata and update etag Directory
            (void)[[NCManageDatabase sharedInstance] addMetadata:metadataFolder];
            [[NCManageDatabase sharedInstance] setDirectoryWithServerUrl:serverUrl serverUrlTo:nil etag:metadataFolder.etag fileID:metadataFolder.fileID encrypted:metadataFolder.e2eEncrypted account:account];
            
            // reload folder ../ *
            [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:metadataFolder.serverUrl fileID:nil action:k_action_NULL];
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                
                NSMutableArray *metadatasForVerifyChange = [NSMutableArray new];
                NSMutableArray *addMetadatas = [NSMutableArray new];
                
                NSArray *recordsInSessions = [[NCManageDatabase sharedInstance] getMetadatasWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ AND serverUrl == %@ AND session != ''", account, serverUrl] sorted:nil ascending:NO];
                
                // ----- Test : (DELETE) -----
                
                NSMutableArray *metadatasNotPresents = [NSMutableArray new];
                
                NSArray *tableMetadatas = [[NCManageDatabase sharedInstance] getMetadatasWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ AND serverUrl == %@ AND session == ''", account, serverUrl] sorted:nil ascending:NO];
                
                for (tableMetadata *record in tableMetadatas) {
                    
                    BOOL fileIDFound = NO;
                    
                    for (tableMetadata *metadata in metadatas) {
                        
                        if ([record.fileID isEqualToString:metadata.fileID]) {
                            fileIDFound = YES;
                            break;
                        }
                    }
                    
                    if (!fileIDFound)
                        [metadatasNotPresents addObject:record];
                }
                
                // delete metadata not present
                for (tableMetadata *metadata in metadatasNotPresents) {
                    
                    [[NSFileManager defaultManager] removeItemAtPath:[CCUtility getDirectoryProviderStorageFileID:metadata.fileID] error:nil];
                    
                    if (metadata.directory && serverUrl) {
                        
                        NSString *dirForDelete = [CCUtility stringAppendServerUrl:serverUrl addFileName:metadata.fileName];
                        
                        [[NCManageDatabase sharedInstance] deleteDirectoryAndSubDirectoryWithServerUrl:dirForDelete account:metadata.account];
                    }
                    
                    [[NCManageDatabase sharedInstance] deleteMetadataWithPredicate:[NSPredicate predicateWithFormat:@"fileID == %@", metadata.fileID]];
                    [[NCManageDatabase sharedInstance] deleteLocalFileWithPredicate:[NSPredicate predicateWithFormat:@"fileID == %@", metadata.fileID]];
                    [[NCManageDatabase sharedInstance] deletePhotosWithFileID:metadata.fileID];
                }
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([metadatasNotPresents count] > 0)
                        [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:serverUrl fileID:nil action:k_action_NULL];
                });
                
                // ----- Test : (MODIFY) -----
                
                for (tableMetadata *metadata in metadatas) {
                    
                    // RECURSIVE DIRECTORY MODE
                    if (metadata.directory) {
                        
                        // Verify if do not exists this Metadata
                        tableMetadata *result = [[NCManageDatabase sharedInstance] getMetadataWithPredicate:[NSPredicate predicateWithFormat:@"fileID == %@", metadata.fileID]];
                        
                        if (!result)
                            (void)[[NCManageDatabase sharedInstance] addMetadata:metadata];
                        
                        [self readFolder:[CCUtility stringAppendServerUrl:serverUrl addFileName:metadata.fileName] selector:selector];
                        
                    } else {
                        
                        if ([selector isEqualToString:selectorReadFolderWithDownload]) {
                            
                            // It's in session
                            BOOL recordInSession = NO;
                            for (tableMetadata *record in recordsInSessions) {
                                if ([record.fileID isEqualToString:metadata.fileID]) {
                                    recordInSession = YES;
                                    break;
                                }
                            }
                            
                            if (recordInSession)
                                continue;
                            
                            // Ohhhh INSERT
                            [metadatasForVerifyChange addObject:metadata];
                        }
                        
                        if ([selector isEqualToString:selectorReadFolder]) {
                            
                            // Verify if do not exists this Metadata
                            tableMetadata *result = [[NCManageDatabase sharedInstance] getMetadataWithPredicate:[NSPredicate predicateWithFormat:@"fileID == %@", metadata.fileID]];
                            
                            if (!result)
                                [addMetadatas addObject:metadata];
                        }
                    }
                }
                
                if ([addMetadatas count] > 0)
                    (void)[[NCManageDatabase sharedInstance] addMetadatas:addMetadatas];
                
                if ([metadatasForVerifyChange count] > 0)
                    [self verifyChangeMedatas:metadatasForVerifyChange serverUrl:serverUrl account:account withDownload:YES];
            });
            
        } else {
        
            // Folder not present, remove it
            if (errorCode == kOCErrorServerPathNotFound) {
                [[NCManageDatabase sharedInstance] deleteDirectoryAndSubDirectoryWithServerUrl:serverUrl account:account];
                [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:serverUrl fileID:nil action:k_action_NULL];
            }
        }
    }];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Read File for Folder & Read File=====
#pragma --------------------------------------------------------------------------------------------

- (void)readFile:(NSString *)fileID fileName:(NSString *)fileName serverUrl:(NSString *)serverUrl selector:(NSString *)selector
{
    [[OCnetworking sharedManager] readFileWithAccount:appDelegate.activeAccount serverUrl:serverUrl fileName:fileName completion:^(NSString *account, tableMetadata *metadata, NSString *message, NSInteger errorCode) {
        
        if (errorCode == 0 && [account isEqualToString:appDelegate.activeAccount]) {
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                
                BOOL withDownload = NO;
                
                if ([selector isEqualToString:selectorReadFileWithDownload])
                    withDownload = YES;
                
                //Add/Update Metadata
                tableMetadata *addMetadata = [[NCManageDatabase sharedInstance] addMetadata:metadata];
                
                if (addMetadata)
                    [self verifyChangeMedatas:[[NSArray alloc] initWithObjects:addMetadata, nil] serverUrl:serverUrl account:appDelegate.activeAccount withDownload:withDownload];
            });
            
        } else if (errorCode == kOCErrorServerPathNotFound) {
            
            [[NCManageDatabase sharedInstance] deleteMetadataWithPredicate:[NSPredicate predicateWithFormat:@"fileID == %@", fileID]];
            [[NCManageDatabase sharedInstance] deleteLocalFileWithPredicate:[NSPredicate predicateWithFormat:@"fileID == %@", fileID]];
            [[NCManageDatabase sharedInstance] deletePhotosWithFileID:fileID];
            
            [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:serverUrl fileID:nil action:k_action_NULL];
        }
    }];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Verify Metadatas =====
#pragma --------------------------------------------------------------------------------------------

// MULTI THREAD
- (void)verifyChangeMedatas:(NSArray *)allRecordMetadatas serverUrl:(NSString *)serverUrl account:(NSString *)account withDownload:(BOOL)withDownload
{
    NSMutableArray *metadatas = [[NSMutableArray alloc] init];
    
    for (tableMetadata *metadata in allRecordMetadatas) {
        
        BOOL changeRev = NO;
        
        // change account
        if ([metadata.account isEqualToString:account] == NO)
            return;
        
        // no dir
        if (metadata.directory)
            continue;
        
        tableLocalFile *localFile = [[NCManageDatabase sharedInstance] getTableLocalFileWithPredicate:[NSPredicate predicateWithFormat:@"fileID == %@", metadata.fileID]];
        
        if (withDownload) {
            
            if (![localFile.etag isEqualToString:metadata.etag] || ![CCUtility fileProviderStorageExists:metadata.fileID fileNameView:metadata.fileNameView])
                changeRev = YES;
            
        } else {
            
            if (localFile && ![localFile.etag isEqualToString:metadata.etag]) // it must be in TableRecord
                changeRev = YES;
        }
        
        if (changeRev) {
            
            // remove & re-create
            [[NSFileManager defaultManager] removeItemAtPath:[CCUtility getDirectoryProviderStorageFileID:metadata.fileID] error:nil];
            [CCUtility getDirectoryProviderStorageFileID:metadata.fileID fileNameView:metadata.fileNameView];
            
            [metadatas addObject:metadata];
        }
        
        // The document file required always a reload 
        if (metadata.hasPreview == 1 && [metadata.typeFile isEqualToString:k_metadataTypeFile_document]) {
             [[NSFileManager defaultManager] removeItemAtPath:[CCUtility getDirectoryProviderStorageIconFileID:metadata.fileID fileNameView:metadata.fileNameView] error:nil];
        }
    }
    
    if ([metadatas count])
        [self SynchronizeMetadatas:metadatas withDownload:withDownload];
}

// MULTI THREAD
- (void)SynchronizeMetadatas:(NSArray *)metadatas withDownload:(BOOL)withDownload
{
    NSString *oldServerUrl;
    NSMutableArray *metadataToAdd = [NSMutableArray new];
    NSMutableArray *serverUrlToReload = [NSMutableArray new];


    for (tableMetadata *metadata in metadatas) {
        
        // Clear date for dorce refresh view
        if (![oldServerUrl isEqualToString:metadata.serverUrl]) {
            oldServerUrl = metadata.serverUrl;
            [serverUrlToReload addObject:metadata.serverUrl];
            [[NCManageDatabase sharedInstance] clearDateReadWithServerUrl:metadata.serverUrl account:metadata.account];
        }
        
        metadata.session = k_download_session;
        metadata.sessionError = @"";
        metadata.sessionSelector = selectorDownloadSynchronize;
        metadata.status = k_metadataStatusWaitDownload;
        
        [metadataToAdd addObject:metadata];
    }
    
    (void)[[NCManageDatabase sharedInstance] addMetadatas:metadataToAdd];
    [appDelegate performSelectorOnMainThread:@selector(loadAutoDownloadUpload) withObject:nil waitUntilDone:YES];
    
    for (NSString *serverUrl in serverUrlToReload) {
        [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:serverUrl fileID:nil action:k_action_NULL];
    }
}

@end
