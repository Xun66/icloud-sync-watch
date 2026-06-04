from __future__ import annotations

import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import icloud_activity
from activity_parser import masked_name_to_regex
from icloud_activity import ActivityParser, Resolver, parse_lines, watch_live


ROOT = Path(__file__).resolve().parent.parent
TARGET_FILE = ROOT / "target_file.log"
TARGET_DIR = ROOT / "temp_dir_fixture"
RENAMED_FILE = ROOT / "renamed_target.log"
RENAMED_DIR = ROOT / "temp_dir_fixture_renamed"
MOVED_DIR_PARENT = ROOT / "moved_parent_fixture"
MOVED_DIR = MOVED_DIR_PARENT / TARGET_DIR.name
PARENT_INODE = str(os.stat(TARGET_FILE.parent).st_ino)
MASKED_NAME = 't{9}e.log'
DIR_NAME = TARGET_DIR.name


def target_dir_file_id() -> str:
    return str(os.stat(TARGET_DIR).st_ino)


class IcloudActivityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        TARGET_FILE.write_text("fixture\n", encoding="utf-8")
        TARGET_DIR.mkdir(exist_ok=True)
        RENAMED_FILE.write_text("fixture\n", encoding="utf-8")
        RENAMED_DIR.mkdir(exist_ok=True)
        MOVED_DIR_PARENT.mkdir(exist_ok=True)
        MOVED_DIR.mkdir(exist_ok=True)

    @classmethod
    def tearDownClass(cls) -> None:
        if TARGET_FILE.exists():
            TARGET_FILE.unlink()
        if TARGET_DIR.exists():
            TARGET_DIR.rmdir()
        if RENAMED_FILE.exists():
            RENAMED_FILE.unlink()
        if MOVED_DIR.exists():
            MOVED_DIR.rmdir()
        if MOVED_DIR_PARENT.exists():
            MOVED_DIR_PARENT.rmdir()
        if RENAMED_DIR.exists():
            RENAMED_DIR.rmdir()

    def test_emits_uploaded_for_local_change_by_default(self) -> None:
        lines = [
            f'[dbg] Handling FSEvent for <i:docID(514576) p:fileID({PARENT_INODE}) n:"{MASKED_NAME}" doc sz:363 m:rw- ct:0 mt:0>',
            f'[note] done executing <J1 ✅  update-item(propagated:<docID(514576) dbver:12 domver:<nil>> target:<id:f3c6be sver:{{blob16}} cver:{{blob41}}> requested:<p:n3c6b1 n:"{MASKED_NAME}" doc sz:363 m:rw-> diffs:content|mtime) why:itemChangedRemotely|contentUpdate> →  <actual:<s:f3c6be p:n3c6b1 n:"{MASKED_NAME}" doc sz:363 m:rw- nsattr:<cap:rwdpfTe-- l:"{MASKED_NAME}" ul:uploading userInfo:<4 keys>>>>',
            f'[info] item changed <FPItem 0x1:f3c6be l:"{MASKED_NAME}" p:n3c6b1 sz:363 bytes cap:rwdpfetT---- ul:uploaded dl:current spd:com.apple.CloudDocs>',
        ]

        self.assertEqual(
            parse_lines(lines, volume_path=ROOT),
            [
                f"uploaded {TARGET_FILE} (fsize: 363)",
            ],
        )

    def test_emits_downloaded_for_remote_fetch_by_default(self) -> None:
        lines = [
            f'[dbg] Handling FSEvent for <i:docID(514576) p:fileID({PARENT_INODE}) n:"{MASKED_NAME}" doc sz:363 m:rw- ct:0 mt:0>',
            f'[info] reconciliation update:     <fs:✅  docID(514576) content:watch sver:fileID({PARENT_INODE})/{MASKED_NAME} cver:115305929@9:sz:363> <-> <fp:✅  f3c6be content:watch sver:{{blob16}} cver:{{blob42}}> doc sched:default',
            '[note] persist job: <FP2 ⏯  fetch-content(f3c6be) why:itemChangedRemotely sched:default>',
            f'[note] done executing <J1 ✅  update-item(propagated:<f3c6be dbver:23 domver:<nil>> target:<id:docID(514576) sver:fileID({PARENT_INODE})/{MASKED_NAME} cver:115305929@11:sz:363> requested:<p:fileID({PARENT_INODE}) n:"{MASKED_NAME}" doc sz:372 m:rw-%<0:unknown:speculativeUpdates>> diffs:content|mtime) why:itemChangedRemotely|contentUpdate> →  <actual:<s:docID(514576) p:fileID({PARENT_INODE}) n:"{MASKED_NAME}" doc sz:372 m:rw->>',
        ]

        self.assertEqual(
            parse_lines(lines, volume_path=ROOT),
            [
                f"downloaded {TARGET_FILE} (fsize: 372)",
            ],
        )

    def test_emits_downloaded_when_path_is_first_resolved_on_completion(self) -> None:
        target = Path("/tmp/翻译乃大道 (余光中).epub")
        lines = [
            '[info] reconciliation update:     <fs:✅  docID(184586) materialize content:watch sver:fileID(32079270)/翻{9}).epub cver:32093178> <-> <fp:✅  f226 content:snap sver:{blob16} cver:{blob34}> doc sched:userInitiated',
            '[note] persist job: <FP1 ⏯  fetch-content(f226) why:materialization|itemChangedRemotely sched:userInitiated>',
            '[note] done executing <J1 ✅  update-item(propagated:<f226 dbver:3 domver:<nil>> target:<id:docID(184586) sver:fileID(32079270)/翻{9}).epub cver:32093178> requested:<p:fileID(32079270) n:"翻{9}).epub" doc sz:424318 m:rw-%<0:high:userRequested> ct:1759510004.0 mt:1759510004.0 lu:1759510038.0 qtn> diffs:dataless) why:materialization|itemChangedRemotely|userRequest|contentUpdate sched:userInitiated> →  <actual:<s:docID(184586) p:fileID(32079270) n:"翻{9}).epub" doc sz:424318 m:rw- ct:1759510004.0 mt:1759510004.0 lu:1759510038.0 xa:c{1}m.a{3}e.f{2}s.f{4}d:{18} v:sver:fileID(32079270)/翻{9}).epub cver:32093178@6:sz:424318> stillPending:evictionUrgency shouldFetch:false>',
        ]

        with patch.object(Resolver, "resolve_doc_path", return_value=target):
            self.assertEqual(
                parse_lines(lines, volume_path=ROOT),
                [
                    f"downloaded {target} (fsize: 424318)",
                ],
            )

    def test_live_parser_emits_downloaded_when_path_is_first_resolved_on_completion(self) -> None:
        target = Path("/tmp/翻译乃大道 (余光中).epub")
        lines = [
            '[info] reconciliation update:     <fs:✅  docID(184586) materialize content:watch sver:fileID(32079270)/翻{9}).epub cver:32093178> <-> <fp:✅  f226 content:snap sver:{blob16} cver:{blob34}> doc sched:userInitiated',
            '[note] persist job: <FP1 ⏯  fetch-content(f226) why:materialization|itemChangedRemotely sched:userInitiated>',
            '[note] done executing <J1 ✅  update-item(propagated:<f226 dbver:3 domver:<nil>> target:<id:docID(184586) sver:fileID(32079270)/翻{9}).epub cver:32093178> requested:<p:fileID(32079270) n:"翻{9}).epub" doc sz:424318 m:rw-%<0:high:userRequested> ct:1759510004.0 mt:1759510004.0 lu:1759510038.0 qtn> diffs:dataless) why:materialization|itemChangedRemotely|userRequest|contentUpdate sched:userInitiated> →  <actual:<s:docID(184586) p:fileID(32079270) n:"翻{9}).epub" doc sz:424318 m:rw- ct:1759510004.0 mt:1759510004.0 lu:1759510038.0 xa:c{1}m.a{3}e.f{2}s.f{4}d:{18} v:sver:fileID(32079270)/翻{9}).epub cver:32093178@6:sz:424318> stillPending:evictionUrgency shouldFetch:false>',
        ]

        with patch.object(Resolver, "resolve_doc_path", return_value=target):
            parser = ActivityParser(resolver=Resolver(volume_path=ROOT))
            output: list[str] = []
            for line in lines:
                output.extend(parser.feed_line(line))

        self.assertEqual(
            output,
            [
                f"downloaded {target} (fsize: 424318)",
            ],
        )

    def test_live_parser_emits_renamed_for_file(self) -> None:
        parser = ActivityParser(resolver=Resolver(volume_path=ROOT))
        parser.doc_paths["184586"] = TARGET_FILE
        line = (
            '[info] trigger: itemUpdatedInFSSnapshot(from: Optional(<s:docID(184586) '
            f'p:fileID({PARENT_INODE}) n:"{MASKED_NAME}" doc sz:363 m:rw->), '
            f'to: Optional(<s:docID(184586) p:fileID({PARENT_INODE}) n:"{RENAMED_FILE.name}" '
            'doc sz:363 m:rw->), diffs: filename|structure)'
        )

        with patch.object(Resolver, "resolve_doc_path", return_value=RENAMED_FILE):
            self.assertEqual(
                parser.feed_line(line),
                [
                    f"renamed {TARGET_FILE} -> {RENAMED_FILE}",
                ],
            )

    def test_live_parser_emits_renamed_dir(self) -> None:
        parser = ActivityParser(resolver=Resolver(volume_path=ROOT))
        dir_file_id = target_dir_file_id()
        parser.provider_paths[dir_file_id] = TARGET_DIR
        line = (
            '[info] trigger: itemUpdatedInFSSnapshot(from: Optional('
            f'<s:fileID({dir_file_id}) p:fileID({PARENT_INODE}) n:"{DIR_NAME}/" dir child:0 m:rwx>), '
            f'to: Optional(<s:fileID({dir_file_id}) p:fileID({PARENT_INODE}) n:"{RENAMED_DIR.name}/" '
            'dir child:0 m:rwx>), diffs: filename|structure)'
        )

        with patch.object(Resolver, "local_dir_path", return_value=RENAMED_DIR):
            self.assertEqual(
                parser.feed_line(line),
                [
                    f"renamed-dir {TARGET_DIR} -> {RENAMED_DIR}",
                ],
            )

    def test_live_parser_emits_moved_dir(self) -> None:
        parser = ActivityParser(resolver=Resolver(volume_path=ROOT))
        dir_file_id = target_dir_file_id()
        parser.provider_paths[dir_file_id] = TARGET_DIR
        moved_parent_id = "999999"
        line = (
            '[info] trigger: itemUpdatedInFSSnapshot(from: Optional('
            f'<s:fileID({dir_file_id}) p:fileID({PARENT_INODE}) n:"{DIR_NAME}/" dir child:0 m:rwx>), '
            f'to: Optional(<s:fileID({dir_file_id}) p:fileID({moved_parent_id}) n:"{DIR_NAME}/" '
            'dir child:0 m:rwx>), diffs: parentID|structure)'
        )

        with patch.object(Resolver, "local_dir_path", return_value=MOVED_DIR):
            self.assertEqual(
                parser.feed_line(line),
                [
                    f"moved-dir {TARGET_DIR} -> {MOVED_DIR}",
                ],
            )

    def test_live_parser_emits_renamed_dir_after_created_dir(self) -> None:
        parser = ActivityParser(resolver=Resolver(volume_path=ROOT))
        dir_file_id = target_dir_file_id()
        create_line = (
            f'[dbg] Handling FSEvent for <i:fileID({dir_file_id}) p:fileID({PARENT_INODE}) '
            f'n:"{DIR_NAME}" dir child:0 m:rwx ct:1780542638.3596895 mt:1780542638.3596895>'
        )
        rename_line = (
            '[info] trigger: itemUpdatedInFSSnapshot(from: Optional('
            f'<s:fileID({dir_file_id}) p:fileID({PARENT_INODE}) n:"{DIR_NAME}/" dir child:0 m:rwx>), '
            f'to: Optional(<s:fileID({dir_file_id}) p:fileID({PARENT_INODE}) n:"{RENAMED_DIR.name}/" '
            'dir child:0 m:rwx>), diffs: filename|structure)'
        )

        with patch.object(Resolver, "local_dir_path", side_effect=[TARGET_DIR, RENAMED_DIR, RENAMED_DIR, RENAMED_DIR]):
            self.assertEqual(parser.feed_line(create_line), [])
            self.assertEqual(
                parser.feed_line(rename_line),
                [
                    f"renamed-dir {TARGET_DIR} -> {RENAMED_DIR}",
                ],
            )

    def test_emits_downloaded_for_real_log_when_name_cannot_be_unmasked(self) -> None:
        target = Path("/tmp/穷查理宝典.epub")
        lines = [
            '[note] persist job: <FP1 ⏯  fetch-content(f34887) why:materialization|itemChangedRemotely sched:userInitiated.1780543723.233155#1780543723.233155>',
            '[note] done executing <J1 ✅  update-item(propagated:<f34887 dbver:0 domver:<nil>> target:<id:docID(370461) sver:fileID(32079262)/穷{150}).epub cver:62660708> requested:<p:fileID(32079262) n:"穷{150}).epub" doc sz:3928878 m:rw-%<0:high:userRequested> ct:1771308918.0 mt:1771308919.0 lu:1771308919.0 qtn> diffs:dataless) why:materialization|itemChangedRemotely|userRequest|contentUpdate sched:userInitiated.1780543723.233155#1780543723.233155 from:<file-ino(116924093)> ⧗persisted>',
            '[note] done executing <J1 ✅  update-item(propagated:<f34887 dbver:0 domver:<nil>> target:<id:docID(370461) sver:fileID(32079262)/穷{150}).epub cver:62660708> requested:<p:fileID(32079262) n:"穷{150}).epub" doc sz:3928878 m:rw-%<0:high:userRequested> ct:1771308918.0 mt:1771308919.0 lu:1771308919.0 qtn> diffs:dataless) why:materialization|itemChangedRemotely|userRequest|contentUpdate sched:userInitiated.1780543723.233155#1780543723.233155> →  <actual:<s:docID(370461) p:fileID(32079262) n:"穷{150}).epub" doc sz:3928878 m:rw- ct:1771308918.0 mt:1771308919.0 lu:1771308919.0 xa:c{1}m.a{3}e.f{2}s.f{4}d:{18} v:sver:fileID(32079262)/穷{150}).epub cver:62660708@6:sz:3928878> stillPending:evictionUrgency shouldFetch:false>',
        ]

        def fake_local_path(item_id: str) -> Path:
            if item_id == "116924093":
                return target
            return Path("/Users/tzz/Library/Mobile Documents/com~apple~CloudDocs/Downloads")

        with patch.object(Resolver, "local_path", side_effect=fake_local_path, create=True):
            self.assertEqual(
                parse_lines(lines, volume_path=ROOT),
                [
                    f"downloaded {target} (fsize: 3928878)",
                ],
            )

    def test_live_parser_emits_renamed_dir_from_real_update_item_log(self) -> None:
        parser = ActivityParser(resolver=Resolver(volume_path=ROOT))
        old_path = ROOT / "old-dir"
        new_path = ROOT / "new-dir"
        parser.provider_paths["116923617"] = old_path
        line = (
            '[info] done executing <J2 ✅  update-item(propagated:<fileID(116923617) dbver:1 domver:<nil>> '
            'target:<id:n3c746 sver:CgA= cver:> requested:<p:n39773 n:"t{2}t" dir child:0 m:rwx '
            'ct:1780543686.5456927 mt:1780543686.5456927 xa:c{1}m.a{3}e.f{2}s.f{4}d:{14}> '
            'diffs:filename|structure) why:itemChangedRemotely sched:utility#1780543688.334938> '
            '→  <actual:<s:n3c746 p:n39773 n:"t{2}t/" dir child:65533 m:rwx ct:1780543686.0 mt:1780543686.0 '
            'unsupported:typeAndCreator v:sver:Cgc1Z2tjdjsx cver: nsattr:<cap:rwdpfTe-- l:"t{2}t" '
            'ul:uploading userInfo:<7 keys> cp:system>> stillPending: shouldFetch:false>'
        )

        with patch.object(Resolver, "local_path", return_value=new_path, create=True):
            self.assertEqual(
                parser.feed_line(line),
                [
                    f"renamed-dir {old_path} -> {new_path}",
                ],
            )

    def test_live_parser_emits_deleted_dir_when_real_log_moves_dir_to_trash(self) -> None:
        parser = ActivityParser(resolver=Resolver(volume_path=ROOT))
        old_path = ROOT / "temp-dir"
        parser.provider_paths["116923617"] = old_path
        line = (
            '[info] done executing <J2 ✅  update-item(propagated:<fileID(116923617) dbver:3 domver:<nil>> '
            'target:<id:n3c746 sver:{blob16} cver:> requested:<p:.trash n:"t{11}3" dir child:0 m:rwx '
            'ct:1780543686.5456927 mt:1780543689.0 xa:c{1}m.a{3}e.f{2}s.f{4}d:{14}> '
            'diffs:filename|parentID|structure) why:itemChangedRemotely sched:utility#1780543693.088181> '
            '→  <actual:<s:n3c746 p:.trash n:"t{11}3/" dir child:65533 m:rwx ct:1780543686.0 mt:1780543689.0 '
            'xa:c{1}m.a{3}e.f{10}r.t{12}k#PN:{6},c{1}m.a{3}e.c{7}s.p{5}e.t{19}k#B:{97} '
            'unsupported:typeAndCreator v:sver:Cgc1Z2tjeDsx cver: nsattr:<cap:rwdpfTe-- l:"t{11}3" '
            'ul:uploading userInfo:<7 keys> cp:system>> stillPending: shouldFetch:false>'
        )

        self.assertEqual(
            parser.feed_line(line),
            [
                f"deleted-dir {old_path}",
            ],
        )

    def test_verbose_mode_emits_uploading_and_reason(self) -> None:
        lines = [
            f'[dbg] Handling FSEvent for <i:docID(514576) p:fileID({PARENT_INODE}) n:"{MASKED_NAME}" doc sz:363 m:rw- ct:0 mt:0>',
            f'[note] done executing <J1 ✅  update-item(propagated:<docID(514576) dbver:12 domver:<nil>> target:<id:f3c6be sver:{{blob16}} cver:{{blob41}}> requested:<p:n3c6b1 n:"{MASKED_NAME}" doc sz:363 m:rw-> diffs:content|mtime) why:itemChangedRemotely|contentUpdate> →  <actual:<s:f3c6be p:n3c6b1 n:"{MASKED_NAME}" doc sz:363 m:rw- nsattr:<cap:rwdpfTe-- l:"{MASKED_NAME}" ul:uploading userInfo:<4 keys>>>>',
            f'[info] item changed <FPItem 0x1:f3c6be l:"{MASKED_NAME}" p:n3c6b1 sz:363 bytes cap:rwdpfetT---- ul:uploaded dl:current spd:com.apple.CloudDocs>',
        ]

        self.assertEqual(
            parse_lines(lines, volume_path=ROOT, verbose=True),
            [
                f"uploading {TARGET_FILE} (fsize: 363; trigger: content|mtime; why: itemChangedRemotely|contentUpdate)",
                f"uploaded {TARGET_FILE} (fsize: 363)",
            ],
        )

    def test_verbose_mode_emits_downloading_and_reason(self) -> None:
        lines = [
            f'[dbg] Handling FSEvent for <i:docID(514576) p:fileID({PARENT_INODE}) n:"{MASKED_NAME}" doc sz:363 m:rw- ct:0 mt:0>',
            f'[info] reconciliation update:     <fs:✅  docID(514576) content:watch sver:fileID({PARENT_INODE})/{MASKED_NAME} cver:115305929@9:sz:363> <-> <fp:✅  f3c6be content:watch sver:{{blob16}} cver:{{blob42}}> doc sched:default',
            '[note] persist job: <FP2 ⏯  fetch-content(f3c6be) why:materialization|userRequest|itemChangedRemotely sched:default>',
            f'[note] done executing <J1 ✅  update-item(propagated:<f3c6be dbver:23 domver:<nil>> target:<id:docID(514576) sver:fileID({PARENT_INODE})/{MASKED_NAME} cver:115305929@11:sz:363> requested:<p:fileID({PARENT_INODE}) n:"{MASKED_NAME}" doc sz:372 m:rw-%<0:unknown:speculativeUpdates>> diffs:content|mtime) why:itemChangedRemotely|contentUpdate> →  <actual:<s:docID(514576) p:fileID({PARENT_INODE}) n:"{MASKED_NAME}" doc sz:372 m:rw->>',
        ]

        self.assertEqual(
            parse_lines(lines, volume_path=ROOT, verbose=True),
            [
                f"downloading {TARGET_FILE} (fsize: 363; why: materialization|userRequest|itemChangedRemotely)",
                f"downloaded {TARGET_FILE} (fsize: 372)",
            ],
        )

    def test_emits_deleted_for_local_delete_by_default(self) -> None:
        lines = [
            f'[dbg] Handling FSEvent for <i:docID(514576) p:fileID({PARENT_INODE}) n:"{MASKED_NAME}" doc sz:363 m:rw- ct:0 mt:0>',
            f'[info] reconciliation delete:  ⬇︎  <fs:▶️  docID(514576) delete:recursive|running content:watch sver:fileID({PARENT_INODE})/{MASKED_NAME} cver:115305929@9:sz:363> <-> <fp:⏯  f3c6be fields:evictionUrgency|structure content:watch sver:CgA= cver:{{blob34}}> doc sched:utility#0 rank:0⏳',
            f'[info] trigger: itemUpdatedInFSSnapshot(from: Optional(<s:docID(514576) p:fileID({PARENT_INODE}) n:"{MASKED_NAME}" doc sz:363 m:rw- ct:0 mt:0 xa:c{{1}}m.a{{3}}e.f{{2}}s.f{{4}}d:{{19}} v:sver:fileID({PARENT_INODE})/{MASKED_NAME} cver:115305929@9:sz:363>), to: nil, diffs: all)',
        ]

        self.assertEqual(
            parse_lines(lines, volume_path=ROOT),
            [
                f"deleted {TARGET_FILE} (fsize: 363)",
            ],
        )

    def test_emits_created_dir_for_local_mkdir(self) -> None:
        dir_file_id = target_dir_file_id()
        lines = [
            f'[info] item changed <i:fileID({dir_file_id}) p:fileID({PARENT_INODE}) n:"{DIR_NAME}" dir child:0 m:rwx ct:1780462111.066761 mt:1780462111.066761>',
            f'[info] reconciliation insert:     <fs:▶️  fileID({dir_file_id}) content:watch> <-> <fp:✅  <unknown>> dir sched:utility#1780462111.455305 rank:0',
            f'[info] trigger: itemUpdatedInFSSnapshot(from: nil, to: Optional(<s:fileID({dir_file_id}) p:fileID({PARENT_INODE}) n:"{DIR_NAME}/" dir child:0 m:rwx ct:1780462111.066761 mt:1780462111.066761>), diffs: all)',
        ]

        self.assertEqual(
            parse_lines(lines, volume_path=ROOT),
            [
                f"created-dir {TARGET_DIR}",
            ],
        )

    def test_emits_deleted_dir_for_local_rmdir(self) -> None:
        dir_file_id = target_dir_file_id()
        lines = [
            f'[info] item changed <i:fileID({dir_file_id}) p:fileID({PARENT_INODE}) n:"{DIR_NAME}" dir child:0 m:rwx ct:1780462111.066761 mt:1780462111.066761>',
            f'[info] reconciliation delete:  ⬇︎  <fs:▶️  fileID({dir_file_id}) delete:recursive|running content:watch sver:fileID({PARENT_INODE})/{DIR_NAME} cver:{dir_file_id}> <-> <fp:⏯  n52 fields:structure content:watch sver:CgU1Z2s3OA== cver:> dir sched:utility#0 rank:0⏳',
            f'[info] trigger: itemUpdatedInFSSnapshot(from: Optional(<s:fileID({dir_file_id}) p:fileID({PARENT_INODE}) n:"{DIR_NAME}/" dir child:0 m:rwx ct:1780462111.066761 mt:1780462111.066761>), to: nil, diffs: all)',
        ]

        self.assertEqual(
            parse_lines(lines, volume_path=ROOT),
            [
                f"deleted-dir {TARGET_DIR}",
            ],
        )

    def test_verbose_mode_emits_deleting_and_deleted(self) -> None:
        lines = [
            f'[dbg] Handling FSEvent for <i:docID(514576) p:fileID({PARENT_INODE}) n:"{MASKED_NAME}" doc sz:363 m:rw- ct:0 mt:0>',
            f'[info] reconciliation delete:  ⬇︎  <fs:▶️  docID(514576) delete:recursive|running content:watch sver:fileID({PARENT_INODE})/{MASKED_NAME} cver:115305929@9:sz:363> <-> <fp:⏯  f3c6be fields:evictionUrgency|structure content:watch sver:CgA= cver:{{blob34}}> doc sched:utility#0 rank:0⏳',
            f'[info] trigger: itemUpdatedInFSSnapshot(from: Optional(<s:docID(514576) p:fileID({PARENT_INODE}) n:"{MASKED_NAME}" doc sz:363 m:rw- ct:0 mt:0 xa:c{{1}}m.a{{3}}e.f{{2}}s.f{{4}}d:{{19}} v:sver:fileID({PARENT_INODE})/{MASKED_NAME} cver:115305929@9:sz:363>), to: nil, diffs: all)',
        ]

        self.assertEqual(
            parse_lines(lines, volume_path=ROOT, verbose=True),
            [
                f"deleting {TARGET_FILE} (fsize: 363; trigger: delete:recursive|running)",
                f"deleted {TARGET_FILE} (fsize: 363)",
            ],
        )

    def test_caches_parent_file_id_resolution(self) -> None:
        resolver = Resolver(volume_path=ROOT)
        stdout = f'directory: "{ROOT}"\n'

        with patch("activity_parser.subprocess.run") as mock_run:
            mock_run.return_value.stdout = stdout
            self.assertEqual(resolver.local_dir_path("123"), ROOT)
            self.assertEqual(resolver.local_dir_path("123"), ROOT)

        self.assertEqual(mock_run.call_count, 1)

    def test_caches_parent_directory_entries_and_child_results(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            parent = Path(tmp)
            first = parent / "alpha.log"
            second = parent / "beta.log"
            first.write_text("a", encoding="utf-8")
            second.write_text("b", encoding="utf-8")

            resolver = Resolver(volume_path=parent)
            original_iterdir = Path.iterdir

            with patch.object(
                Path,
                "iterdir",
                autospec=True,
                side_effect=lambda path_self: original_iterdir(path_self),
            ) as mock_iterdir:
                self.assertEqual(resolver.resolve_child(parent, "a{3}a.log"), first)
                self.assertEqual(resolver.resolve_child(parent, "a{3}a.log"), first)
                self.assertEqual(resolver.resolve_child(parent, "b{2}a.log"), second)

            self.assertEqual(mock_iterdir.call_count, 1)

    def test_dir_entries_cache_evicts_oldest_parent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            parent_one = root / "one"
            parent_two = root / "two"
            parent_three = root / "three"
            for parent, filename in (
                (parent_one, "alpha.log"),
                (parent_two, "beta.log"),
                (parent_three, "gamma.log"),
            ):
                parent.mkdir()
                (parent / filename).write_text("x", encoding="utf-8")

            resolver = Resolver(volume_path=root)
            resolver.dir_entries_cache_max_entries = 2

            self.assertIsNotNone(resolver.resolve_child(parent_one, "a{3}a.log"))
            self.assertIsNotNone(resolver.resolve_child(parent_two, "b{2}a.log"))
            self.assertEqual(set(resolver.dir_entries_cache), {str(parent_one), str(parent_two)})

            self.assertIsNotNone(resolver.resolve_child(parent_three, "g{3}a.log"))
            self.assertEqual(set(resolver.dir_entries_cache), {str(parent_two), str(parent_three)})

    def test_resolve_child_refreshes_after_initial_miss(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            parent = Path(tmp)
            resolver = Resolver(volume_path=parent)
            masked_name = "p{30}m.apk"
            target = parent / "printershare_v11.16.5_downcc.com.apk"

            self.assertIsNone(resolver.resolve_child(parent, masked_name))
            target.write_text("fixture", encoding="utf-8")

            self.assertEqual(resolver.resolve_child(parent, masked_name), target)

    def test_masked_name_counts_unicode_code_points(self) -> None:
        self.assertIsNotNone(masked_name_to_regex("翻{4}.epub").fullmatch("翻译乃大道.epub"))
        self.assertIsNone(masked_name_to_regex("翻{3}.epub").fullmatch("翻译乃大道.epub"))

    def test_verbose_mode_reports_decode_reason_when_directory_listing_is_denied(self) -> None:
        masked_target = Path("/tmp/p{30}m.apk")
        lines = [
            '[info] reconciliation update:     <fs:✅  docID(700001) materialize content:watch sver:fileID(32079262)/p{30}m.apk cver:1> <-> <fp:✅  f70001 content:snap sver:{blob16} cver:{blob34}> doc sched:userInitiated',
            '[note] persist job: <FP1 ⏯  fetch-content(f70001) why:materialization|itemChangedRemotely sched:userInitiated>',
            '[note] done executing <J1 ✅  update-item(propagated:<f70001 dbver:0 domver:<nil>> target:<id:docID(700001) sver:fileID(32079262)/p{30}m.apk cver:1> requested:<p:fileID(32079262) n:"p{30}m.apk" doc sz:2388025 m:rw-%<0:high:userRequested>> diffs:dataless) why:materialization|itemChangedRemotely|userRequest|contentUpdate sched:userInitiated> →  <actual:<s:docID(700001) p:fileID(32079262) n:"p{30}m.apk" doc sz:2388025 m:rw->>',
        ]

        with patch.object(Resolver, "local_dir_path", return_value=Path("/tmp")):
            with patch.object(Resolver, "resolve_doc_path", return_value=None):
                with patch.object(Resolver, "child_resolution_reason", return_value="dir-list-denied", create=True):
                    self.assertEqual(
                        parse_lines(lines, volume_path=ROOT, verbose=True),
                        [
                            "downloading /tmp/p{30}m.apk (fsize: 2388025; decode: dir-list-denied; why: materialization|itemChangedRemotely)",
                            "downloaded /tmp/p{30}m.apk (fsize: 2388025; decode: dir-list-denied)",
                        ],
                    )

    def test_live_verbose_mode_reports_decode_reason_when_name_is_ambiguous(self) -> None:
        parser = ActivityParser(resolver=Resolver(volume_path=ROOT), verbose=True)
        lines = [
            '[info] reconciliation update:     <fs:✅  docID(700002) materialize content:watch sver:fileID(32079262)/翻{9}).epub cver:2> <-> <fp:✅  f70002 content:snap sver:{blob16} cver:{blob34}> doc sched:userInitiated',
            '[note] persist job: <FP1 ⏯  fetch-content(f70002) why:materialization|itemChangedRemotely sched:userInitiated>',
            '[note] done executing <J1 ✅  update-item(propagated:<f70002 dbver:0 domver:<nil>> target:<id:docID(700002) sver:fileID(32079262)/翻{9}).epub cver:2> requested:<p:fileID(32079262) n:"翻{9}).epub" doc sz:424318 m:rw-%<0:high:userRequested>> diffs:dataless) why:materialization|itemChangedRemotely|userRequest|contentUpdate sched:userInitiated> →  <actual:<s:docID(700002) p:fileID(32079262) n:"翻{9}).epub" doc sz:424318 m:rw->>',
        ]

        with patch.object(Resolver, "local_dir_path", return_value=Path("/tmp")):
            with patch.object(Resolver, "resolve_doc_path", return_value=None):
                with patch.object(Resolver, "child_resolution_reason", return_value="ambiguous-match", create=True):
                    output: list[str] = []
                    for line in lines:
                        output.extend(parser.feed_line(line))

        self.assertEqual(
            output,
            [
                "downloaded /tmp/翻{9}).epub (fsize: 424318; decode: ambiguous-match)",
            ],
        )

    def test_main_without_logs_uses_live_mode_on_tty(self) -> None:
        with patch.object(icloud_activity.sys.stdin, "isatty", return_value=True):
            with patch("icloud_activity.watch_live", return_value=0) as mock_watch:
                self.assertEqual(icloud_activity.main([]), 0)

        mock_watch.assert_called_once()

    def test_watch_live_reports_ready_and_emits_streamed_events(self) -> None:
        status_stream = io.StringIO()
        output_stream = io.StringIO()
        lines = [
            f'[dbg] Handling FSEvent for <i:docID(514576) p:fileID({PARENT_INODE}) n:"{MASKED_NAME}" doc sz:363 m:rw- ct:0 mt:0>\n',
            f'[note] done executing <J1 ✅  update-item(propagated:<docID(514576) dbver:12 domver:<nil>> target:<id:f3c6be sver:{{blob16}} cver:{{blob41}}> requested:<p:n3c6b1 n:"{MASKED_NAME}" doc sz:363 m:rw-> diffs:content|mtime) why:itemChangedRemotely|contentUpdate> →  <actual:<s:f3c6be p:n3c6b1 n:"{MASKED_NAME}" doc sz:363 m:rw- nsattr:<cap:rwdpfTe-- l:"{MASKED_NAME}" ul:uploading userInfo:<4 keys>>>>\n',
            f'[info] item changed <FPItem 0x1:f3c6be l:"{MASKED_NAME}" p:n3c6b1 sz:363 bytes cap:rwdpfetT---- ul:uploaded dl:current spd:com.apple.CloudDocs>\n',
        ]

        class FakeProcess:
            def __init__(self, stream_lines: list[str]) -> None:
                self.stdout = stream_lines

            def wait(self) -> int:
                return 0

        with patch.object(Resolver, "local_dir_path", return_value=ROOT):
            with patch("icloud_activity.subprocess.Popen", return_value=FakeProcess(lines)):
                exit_code = watch_live(
                    volume_path=ROOT,
                    status_stream=status_stream,
                    output_stream=output_stream,
                )

        self.assertEqual(exit_code, 0)
        self.assertIn("Watching live iCloud activity", status_stream.getvalue())
        self.assertEqual(
            output_stream.getvalue().splitlines(),
            [
                f"uploaded {TARGET_FILE} (fsize: 363)",
            ],
        )

    def test_watch_live_exits_cleanly_on_ctrl_c(self) -> None:
        status_stream = io.StringIO()

        class InterruptingStream:
            def __iter__(self) -> "InterruptingStream":
                return self

            def __next__(self) -> str:
                raise KeyboardInterrupt

        class FakeProcess:
            def __init__(self) -> None:
                self.stdout = InterruptingStream()
                self.terminated = False

            def terminate(self) -> None:
                self.terminated = True

            def wait(self) -> int:
                return 0

        fake_process = FakeProcess()

        with patch("icloud_activity.subprocess.Popen", return_value=fake_process):
            exit_code = watch_live(volume_path=ROOT, status_stream=status_stream)

        self.assertEqual(exit_code, 130)
        self.assertTrue(fake_process.terminated)
        self.assertIn("Watching live iCloud activity", status_stream.getvalue())


if __name__ == "__main__":
    unittest.main()
