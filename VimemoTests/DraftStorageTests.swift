import XCTest
import UIKit
@testable import Vimemo

@MainActor final class DraftStorageTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var source: URL { Bundle(for: ProjectStore.self).url(forResource: "Demo", withExtension: "mov")! }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DraftStorage-\(UUID().uuidString)")
        suite = "DraftStorage-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suite)
    }
    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    private func photo() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
    }
    func testDefaultSavingAndDisabledEditsPreserveExistingDraft() async throws {
        let store = ProjectStore(root: root, defaults: defaults)
        XCTAssertTrue(store.savesDrafts)
        var project = try await store.importVideo(source, title: "Saved")
        store.setSavesDrafts(false)
        store.beginEditing(project.id)
        project.title = "Unsaved edit"
        project.clips[0].coverPhotoFilename = try store.importCoverPhoto(photo(), project: project)
        let temporaryCover = store.url(for: project.clips[0].coverPhotoFilename!)
        store.update(project); store.persist(); store.cleanTemporaryFiles()
        XCTAssertTrue(exists(temporaryCover), "An open cover picker/editor must keep its files")
        store.endEditing(project.id)
        XCTAssertEqual(store.projects.first?.title, "Saved")
        XCTAssertFalse(exists(temporaryCover))
        let restored = ProjectStore(root: root, defaults: defaults)
        XCTAssertFalse(restored.savesDrafts)
        XCTAssertEqual(restored.projects.first?.title, "Saved")
        XCTAssertTrue(exists(store.url(for: project.filename)))
    }
    func testUnsavedExportKeepsInputsUntilCompletionAndPreservesResult() async throws {
        let store = ProjectStore(root: root, defaults: defaults)
        store.setSavesDrafts(false)
        var project = try await store.importVideo(source, title: "Temporary")
        store.beginEditing(project.id)
        project.settings.format = .photo
        project.clips[0].coverPhotoFilename = try store.importCoverPhoto(photo(), project: project)
        store.update(project)
        let lease = store.retainExportInputs([project])
        let folder = root.appendingPathComponent("Exports/\(UUID().uuidString)")
        store.protectExportFolder(folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let partial = folder.appendingPathComponent("partial")
        try Data([1]).write(to: partial)
        store.endEditing(project.id)
        store.clearTemporaryCache()
        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertTrue(exists(store.url(for: project.filename)))
        XCTAssertTrue(exists(store.url(for: project.clips[0].coverPhotoFilename!)))
        XCTAssertTrue(exists(partial), "Active exports must survive cache cleanup")
        let media = try await LivePhotoExporter().export(source: store.url(for: project.filename), project: project, clip: project.clips[0], directory: folder) { _ in }
        try? FileManager.default.removeItem(at: partial)
        _ = store.record(media, project: project, saved: false)
        store.releaseExportFolder(folder)
        store.releaseExportInputs(lease)
        XCTAssertFalse(exists(store.url(for: project.filename)))
        XCTAssertTrue(exists(source), "Original video must remain untouched")
        let restored = ProjectStore(root: root, defaults: defaults)
        XCTAssertTrue(restored.projects.isEmpty)
        XCTAssertEqual(restored.exports.count, 1)
        XCTAssertTrue(exists(media.urls[0]))
    }
    func testReenablingSavingPromotesCurrentSession() async throws {
        let store = ProjectStore(root: root, defaults: defaults)
        store.setSavesDrafts(false)
        var project = try await store.importVideo(source, title: "Temporary")
        project.title = "Keep this edit"; store.update(project)
        store.setSavesDrafts(true)
        store.endWorkspaceSession()
        let restored = ProjectStore(root: root, defaults: defaults)
        XCTAssertEqual(restored.projects.first?.title, "Keep this edit")
        XCTAssertTrue(exists(restored.url(for: project.filename)))
        XCTAssertNotEqual(try restored.url(for: project.filename).deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }
    func testInterruptedSessionAndOrphanOutputsAreCleanedAtLaunch() async throws {
        let store = ProjectStore(root: root, defaults: defaults)
        store.setSavesDrafts(false)
        let project = try await store.importVideo(source, title: "Interrupted")
        let orphan = root.appendingPathComponent("Exports/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try Data([1]).write(to: orphan.appendingPathComponent("partial.mov"))
        _ = ProjectStore(root: root, defaults: defaults)
        XCTAssertFalse(exists(store.url(for: project.filename)))
        XCTAssertFalse(exists(orphan))
    }
    func testCorruptLibraryPreservesRecoverableFilesAndForeignFolders() throws {
        let media = root.appendingPathComponent("Projects/\(UUID().uuidString)")
        let foreign = root.appendingPathComponent("Exports/unrecognized")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: root.appendingPathComponent("library.json"))
        let store = ProjectStore(root: root, defaults: defaults)
        XCTAssertNotNil(store.errorMessage)
        store.persist(); store.clearTemporaryCache()
        _ = ProjectStore(root: root, defaults: defaults)
        XCTAssertTrue(exists(media)); XCTAssertTrue(exists(foreign))
    }
    func testReplacingCoversReclaimsOnlyUnreferencedPhotosAndDeleteWaitsForExport() async throws {
        let store = ProjectStore(root: root, defaults: defaults)
        var project = try await store.importVideo(source, title: "Covers")
        store.beginEditing(project.id)
        let old = try store.importCoverPhoto(photo(), project: project)
        project.clips[0].coverPhotoFilename = old; store.update(project); store.persist()
        let lease = store.retainExportInputs([project])
        let new = try store.importCoverPhoto(photo(), project: project)
        project.clips[0].coverPhotoFilename = new; store.update(project); store.persist()
        store.endEditing(project.id)
        XCTAssertTrue(exists(store.url(for: old)))
        store.releaseExportInputs(lease)
        XCTAssertFalse(exists(store.url(for: old)))
        XCTAssertTrue(exists(store.url(for: new)))
        let deletionLease = store.retainExportInputs([project])
        store.delete(project)
        XCTAssertTrue(exists(store.url(for: project.filename)))
        store.releaseExportInputs(deletionLease)
        XCTAssertFalse(exists(store.url(for: project.filename)))
    }
    func testCoordinatorFinishesUnsavedExportAfterLeavingWorkspace() async throws {
        let store = ProjectStore(root: root, defaults: defaults)
        store.setSavesDrafts(false)
        var project = try await store.importVideo(source, title: "Queue")
        project.settings.format = .photo; store.update(project)
        let coordinator = ExportCoordinator()
        XCTAssertTrue(coordinator.start(projects: [project], store: store, saveToPhotos: false, purchases: PurchaseStore()))
        store.endWorkspaceSession(); store.clearTemporaryCache()
        XCTAssertTrue(exists(store.url(for: project.filename)))
        for _ in 0..<100 where coordinator.running { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(coordinator.running)
        XCTAssertNil(coordinator.errorMessage)
        XCTAssertEqual(coordinator.completed.count, 1)
        XCTAssertFalse(exists(store.url(for: project.filename)))
        let restored = ProjectStore(root: root, defaults: defaults)
        XCTAssertTrue(restored.projects.isEmpty)
        XCTAssertEqual(restored.exports.count, 1)
    }
    func testCleanupRefusesSymlinkAndInvalidImportRemovesPartialFolder() async throws {
        let store = ProjectStore(root: root, defaults: defaults)
        let outside = root.appendingPathComponent("Keep")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let sentinel = outside.appendingPathComponent("original.mov")
        try Data([1, 2, 3]).write(to: sentinel)
        let link = root.appendingPathComponent("Exports/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        store.clearTemporaryCache()
        XCTAssertTrue(exists(sentinel)); XCTAssertTrue(exists(link))
        do { _ = try await store.importVideo(sentinel, title: nil); XCTFail("Invalid movie should fail") }
        catch {
            let failure = try XCTUnwrap(error as? MediaStageError)
            XCTAssertEqual(failure.stage, "读取本地视频信息")
            XCTAssertFalse(failure.localizedDescription.contains(sentinel.path))
        }
        let folders = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Projects").path)
        XCTAssertTrue(folders.isEmpty)
        XCTAssertTrue(exists(sentinel))
    }

    func testMissingImportReportsCopyStageWithoutCreatingDraft() async throws {
        let store = ProjectStore(root: root, defaults: defaults)
        let missing = root.appendingPathComponent("not-downloaded.mov")
        do { _ = try await store.importVideo(missing, title: "Private title"); XCTFail("Missing source should fail") }
        catch {
            let failure = try XCTUnwrap(error as? MediaStageError)
            XCTAssertEqual(failure.stage, "获取并复制视频到本机")
            XCTAssertFalse(failure.localizedDescription.contains(missing.path))
            XCTAssertFalse(failure.localizedDescription.contains("Private title"))
        }
        XCTAssertTrue(store.projects.isEmpty)
        let folders = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Projects").path)
        XCTAssertTrue(folders.isEmpty)
    }

    func testEmptyDeliveredVideoIsRejectedBeforeCreatingDraft() async throws {
        let store = ProjectStore(root: root, defaults: defaults)
        let empty = root.appendingPathComponent("empty.mov")
        try Data().write(to: empty)
        do { _ = try await store.importVideo(empty, title: nil); XCTFail("Empty delivery should fail") }
        catch {
            let failure = try XCTUnwrap(error as? MediaStageError)
            XCTAssertEqual(failure.stage, "获取并复制视频到本机")
        }
        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertTrue(exists(empty))
        let folders = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Projects").path)
        XCTAssertTrue(folders.isEmpty)
    }

    func testBulkDraftDeletionPreservesUnselectedDraftOutputsAndLeasedInputs() async throws {
        let store = ProjectStore(root: root, defaults: defaults)
        let first = try await store.importVideo(source, title: "First")
        let second = try await store.importVideo(source, title: "Second")
        let kept = try await store.importVideo(source, title: "Keep")
        let record = try makeOutput(store, project: first)
        let lease = store.retainExportInputs([first])
        store.setSavesDrafts(false)
        XCTAssertTrue(store.deleteProjects(ids: [first.id, second.id]))
        XCTAssertEqual(store.projects.map(\.id), [kept.id])
        XCTAssertTrue(exists(store.url(for: first.filename)), "Active export inputs must survive bulk deletion")
        XCTAssertFalse(exists(store.url(for: second.filename)))
        XCTAssertTrue(exists(store.url(for: kept.filename)))
        XCTAssertTrue(exists(store.url(for: record.files[0])), "Deleting drafts must preserve completed works")
        store.releaseExportInputs(lease)
        XCTAssertFalse(exists(store.url(for: first.filename)))
        let restored = ProjectStore(root: root, defaults: defaults)
        XCTAssertEqual(restored.projects.map(\.id), [kept.id])
        XCTAssertEqual(restored.exports.map(\.id), [record.id])
        XCTAssertTrue(exists(source), "The original imported video is never deleted")
    }

    func testBulkExportDeletionPreservesDraftsAndSharedOrActiveOutputFolders() async throws {
        let store = ProjectStore(root: root, defaults: defaults)
        let project = try await store.importVideo(source, title: "Keep draft")
        let first = try makeOutput(store, project: project)
        let sharedFolder = store.url(for: first.files[0]).deletingLastPathComponent()
        let kept = try makeOutput(store, project: project, folder: sharedFolder)
        let second = try makeOutput(store, project: project)
        let activeFolder = store.url(for: second.files[0]).deletingLastPathComponent()
        store.protectExportFolder(activeFolder)
        XCTAssertTrue(store.deleteExports(ids: [first.id, second.id]))
        XCTAssertEqual(store.exports.map(\.id), [kept.id])
        XCTAssertTrue(exists(store.url(for: kept.files[0])), "A selected record must not delete a surviving record's folder")
        XCTAssertTrue(exists(activeFolder))
        XCTAssertTrue(exists(store.url(for: project.filename)))
        store.releaseExportFolder(activeFolder)
        store.clearTemporaryCache()
        XCTAssertFalse(exists(activeFolder))
        XCTAssertTrue(exists(sharedFolder))
        let restored = ProjectStore(root: root, defaults: defaults)
        XCTAssertEqual(restored.exports.map(\.id), [kept.id])
    }

    func testBulkDeletionRollsBackWhenLibraryCannotBeSaved() async throws {
        let store = ProjectStore(root: root, defaults: defaults)
        let project = try await store.importVideo(source, title: "Keep on failure")
        let record = try makeOutput(store, project: project)
        let index = root.appendingPathComponent("library.json")
        let original = try Data(contentsOf: index)
        try FileManager.default.removeItem(at: index)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: index); try? original.write(to: index) }
        XCTAssertFalse(store.deleteProjects(ids: [project.id]))
        XCTAssertEqual(store.projects.map(\.id), [project.id])
        XCTAssertFalse(store.deleteExports(ids: [record.id]))
        XCTAssertEqual(store.exports.map(\.id), [record.id])
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(exists(store.url(for: project.filename)))
        XCTAssertTrue(exists(store.url(for: record.files[0])))
    }

    private func makeOutput(_ store: ProjectStore, project: VideoProject, folder: URL? = nil) throws -> ExportRecord {
        let directory = folder ?? root.appendingPathComponent("Exports/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("\(UUID().uuidString).jpg")
        try photo().write(to: output)
        return store.record(ExportedMedia(directory: directory, urls: [output], thumbnailURL: output,
                                          format: .photo, duration: 1), project: project, saved: false)
    }

}
