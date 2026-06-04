from __future__ import annotations

import os
import re
import subprocess
from collections import OrderedDict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


DOC_ITEM_RE = re.compile(r'<[is]:docID\((\d+)\)\s+p:fileID\((\d+)\)\s+n:"([^"]+)"')
DIR_ITEM_RE = re.compile(r'<[is]:fileID\((\d+)\)\s+p:fileID\((\d+)\)\s+n:"([^"]+)"\s+dir\b')
RECONCILE_RE = re.compile(
    r'<fs:[^>]*?(docID|fileID)\(([^)]+)\)[^>]*?>\s*<->\s*<fp:[^>]*?\s([a-z0-9]+)\s'
)
PROP_DOC_TARGET_RE = re.compile(r'propagated:<docID\((\d+)\).*?target:<id:([a-z0-9]+)\b')
PROP_DOC_ACTUAL_RE = re.compile(r'propagated:<docID\((\d+)\).*?<actual:<s:([a-z0-9]+)\b')
PROP_FILE_TARGET_RE = re.compile(r'propagated:<fileID\((\d+)\).*?target:<id:([a-z0-9]+)\b')
PROVIDER_ITEM_RE = re.compile(r'<s:([a-z0-9]+)\s+p:([a-z0-9]+)\s+n:"([^"]+)"\s+doc')

FP_FETCH_RE = re.compile(r'<FP\d+\s+[^\n>]*fetch-content\(([^)]+)\)')
DOWNLOAD_END_RE = re.compile(
    r'done executing <J\d+ ✅  update-item\(.*target:<id:docID\((\d+)\).*why:[^>]*itemChangedRemotely'
)
DIR_CREATE_START_RE = re.compile(r'reconciliation insert:.*<fs:[^>]*fileID\((\d+)\)[^>]*>.*\sdir\b')
DIR_CREATE_END_RE = re.compile(
    r'itemUpdatedInFSSnapshot\(from: nil, to: Optional\(<s:fileID\((\d+)\).*?\sdir\b.*?\), diffs: all\)'
)
DELETE_START_RE = re.compile(r'reconciliation delete:.*<fs:[^>]*docID\((\d+)\)[^>]*delete:([A-Za-z0-9_|-]+)')
DELETE_END_RE = re.compile(r'itemUpdatedInFSSnapshot\(from: Optional\(<s:docID\((\d+)\).*?\), to: nil, diffs: all\)')
DIR_DELETE_START_RE = re.compile(
    r'reconciliation delete:.*<fs:[^>]*fileID\((\d+)\)[^>]*delete:([A-Za-z0-9_|-]+).*?>.*\sdir\b'
)
DIR_DELETE_END_RE = re.compile(
    r'itemUpdatedInFSSnapshot\(from: Optional\(<s:fileID\((\d+)\).*?\sdir\b.*?\), to: nil, diffs: all\)'
)
DOC_PATH_UPDATE_RE = re.compile(
    r'itemUpdatedInFSSnapshot\(from: Optional\(<s:docID\((\d+)\)\s+p:fileID\((\d+)\)\s+n:"([^"]+)"'
    r'.*?\), to: Optional\(<s:docID\(\1\)\s+p:fileID\((\d+)\)\s+n:"([^"]+)"'
    r'.*?\), diffs:\s*([A-Za-z0-9_| ]+)\)'
)
DIR_PATH_UPDATE_RE = re.compile(
    r'itemUpdatedInFSSnapshot\(from: Optional\(<s:fileID\((\d+)\)\s+p:fileID\((\d+)\)\s+n:"([^"]+)"\s+dir'
    r'.*?\), to: Optional\(<s:fileID\(\1\)\s+p:fileID\((\d+)\)\s+n:"([^"]+)"\s+dir'
    r'.*?\), diffs:\s*([A-Za-z0-9_| ]+)\)'
)
DOC_ID_RE = re.compile(r'\bdocID\((\d+)\)')
FP_ITEM_RE = re.compile(r'FPItem [^:]+:([a-z0-9]+)\b')
PROVIDER_DOC_RE = re.compile(r'<s:([a-z0-9]+)\s+p:[^>]+n:"[^"]+"\s+doc')
DIFFS_RE = re.compile(r'diffs:([A-Za-z0-9_|-]+)')
WHY_RE = re.compile(r'why:([A-Za-z0-9_|-]+)')
SIZE_RE = re.compile(r'\bsz:(\d+)\b')
FILE_INO_RE = re.compile(r'(?:file-ino|content:fid)\((\d+)\)')
FILE_PATH_RE = re.compile(r'file: "([^"]+)"')
DIR_SNAPSHOT_CHANGE_RE = re.compile(
    r'FS snapshot mutation: update<s:fileID\((\d+)\)\s+p:([^ ]+)\s+n:"([^"]+)"\s+dir.*?>\s+diffs:([A-Za-z0-9_|-]+)\b'
)
DIR_UPDATE_COMPLETION_RE = re.compile(
    r'done executing <J\d+ .*?update-item\(propagated:<fileID\((\d+)\).*?'
    r'requested:<p:([^ ]+) n:"([^"]+)" dir .*?diffs:([A-Za-z0-9_|-]+)\)'
)


def masked_name_to_regex(masked_name: str) -> re.Pattern[str]:
    parts: list[str] = ["^"]
    i = 0
    while i < len(masked_name):
        char = masked_name[i]
        if char == "{":
            j = masked_name.find("}", i)
            if j == -1:
                parts.append(re.escape(char))
                i += 1
                continue
            count_text = masked_name[i + 1 : j]
            if count_text.isdigit():
                parts.append(f".{{{count_text}}}")
                i = j + 1
                continue
        parts.append(re.escape(char))
        i += 1
    parts.append("$")
    return re.compile("".join(parts))


@dataclass(frozen=True)
class TransitionSpec:
    state_attr: str
    start_label: str | None
    end_label: str
    start_getter: str | None
    end_getter: str
    completion_policy: str = "emit_once"
    file_only: bool = False
    include_size: bool = False


@dataclass
class Resolver:
    volume_path: Path
    device_id: int = field(init=False)
    local_path_cache: dict[str, Path | None] = field(default_factory=dict)
    dir_entries_cache: OrderedDict[str, list[Path] | None] = field(default_factory=OrderedDict)
    dir_entries_failures: dict[str, str] = field(default_factory=dict)
    dir_entries_cache_max_entries: int = 256
    child_cache: dict[tuple[str, str], Path | None] = field(default_factory=dict)
    child_resolution_failures: dict[tuple[str, str], str] = field(default_factory=dict)

    def __post_init__(self) -> None:
        self.device_id = os.stat(self.volume_path).st_dev

    def local_path(self, item_id: str) -> Path | None:
        if item_id in self.local_path_cache:
            return self.local_path_cache[item_id]

        path = Path(f"/.vol/{self.device_id}/{item_id}")
        try:
            result = subprocess.run(
                ["GetFileInfo", str(path)],
                capture_output=True,
                text=True,
                check=True,
            )
        except (OSError, subprocess.CalledProcessError):
            self.local_path_cache[item_id] = None
            return None

        match = FILE_PATH_RE.search(result.stdout)
        if match:
            resolved = Path(match.group(1))
        else:
            directory_match = re.search(r'directory: "([^"]+)"', result.stdout)
            resolved = Path(directory_match.group(1)) if directory_match else None
        self.local_path_cache[item_id] = resolved
        return resolved

    def local_dir_path(self, file_id: str) -> Path | None:
        return self.local_path(file_id)

    def resolve_doc_path(self, parent_file_id: str, masked_name: str) -> Path | None:
        parent = self.local_dir_path(parent_file_id)
        if parent is None:
            return None
        return self.resolve_child(parent, masked_name)

    def masked_child_path(self, parent_file_id: str, masked_name: str) -> Path | None:
        parent = self.local_dir_path(parent_file_id)
        if parent is None:
            return None
        return parent / masked_name.rstrip("/")

    def resolve_child(self, parent: Path, masked_name: str) -> Path | None:
        key = (str(parent), masked_name)
        if key in self.child_cache:
            return self.child_cache[key]

        resolved, reason = self._resolve_child_once(parent, masked_name)
        if resolved is None and str(parent) in self.dir_entries_cache:
            resolved, reason = self._resolve_child_once(parent, masked_name, refresh=True)
        if resolved is not None:
            self.child_cache[key] = resolved
            self.child_resolution_failures.pop(key, None)
        elif reason is not None:
            self.child_resolution_failures[key] = reason
        return resolved

    def child_resolution_reason(self, parent: Path, masked_name: str) -> str | None:
        return self.child_resolution_failures.get((str(parent), masked_name))

    def _resolve_child_once(self, parent: Path, masked_name: str, *, refresh: bool = False) -> tuple[Path | None, str | None]:
        entries = self._dir_entries(parent, refresh=refresh)
        if entries is None:
            return None, self.dir_entries_failures.get(str(parent))

        exact = parent / masked_name
        if exact.exists():
            return exact, None

        matcher = masked_name_to_regex(masked_name.rstrip("/"))
        candidates = [entry for entry in entries if matcher.fullmatch(entry.name)]
        if masked_name.endswith("/"):
            candidates = [entry for entry in candidates if entry.is_dir()]
        if len(candidates) == 1:
            return candidates[0], None
        if len(candidates) > 1:
            return None, "ambiguous-match"
        return None, "no-match"

    def _dir_entries(self, parent: Path, *, refresh: bool = False) -> list[Path] | None:
        key = str(parent)
        if refresh:
            self.dir_entries_cache.pop(key, None)
            self._drop_child_cache_for_parent(parent)

        if key in self.dir_entries_cache:
            self.dir_entries_cache.move_to_end(key)
            return self.dir_entries_cache[key]

        if not parent.is_dir():
            self.dir_entries_cache[key] = None
            self.dir_entries_failures[key] = "parent-not-dir"
            self._trim_dir_entries_cache()
            return None

        try:
            entries = list(parent.iterdir())
        except PermissionError:
            self.dir_entries_cache[key] = None
            self.dir_entries_failures[key] = "dir-list-denied"
            self._trim_dir_entries_cache()
            return None
        except OSError:
            self.dir_entries_cache[key] = None
            self.dir_entries_failures[key] = "dir-list-failed"
            self._trim_dir_entries_cache()
            return None

        self.dir_entries_cache[key] = entries
        self.dir_entries_failures.pop(key, None)
        self._trim_dir_entries_cache()
        return entries

    def _drop_child_cache_for_parent(self, parent: Path) -> None:
        prefix = str(parent)
        for key in [child_key for child_key in self.child_cache if child_key[0] == prefix]:
            del self.child_cache[key]

    def _trim_dir_entries_cache(self) -> None:
        while len(self.dir_entries_cache) > self.dir_entries_cache_max_entries:
            self.dir_entries_cache.popitem(last=False)


@dataclass
class ActivityParser:
    resolver: Resolver
    verbose: bool = False
    doc_paths: dict[str, Path] = field(default_factory=dict)
    provider_paths: dict[str, Path] = field(default_factory=dict)
    upload_state: dict[Path, str] = field(default_factory=dict)
    download_state: dict[Path, str] = field(default_factory=dict)
    delete_state: dict[Path, str] = field(default_factory=dict)
    dir_create_state: dict[Path, str] = field(default_factory=dict)
    dir_delete_state: dict[Path, str] = field(default_factory=dict)
    path_sizes: dict[Path, int] = field(default_factory=dict)
    path_decode_failures: dict[Path, str] = field(default_factory=dict)

    TRANSITIONS: tuple[TransitionSpec, ...] = (
        TransitionSpec(
            state_attr="upload_state",
            start_label="uploading",
            end_label="uploaded",
            start_getter="_path_for_uploading",
            end_getter="_path_for_uploaded",
            completion_policy="require_start",
            file_only=True,
            include_size=True,
        ),
        TransitionSpec(
            state_attr="download_state",
            start_label="downloading",
            end_label="downloaded",
            start_getter="_path_for_downloading",
            end_getter="_path_for_downloaded",
            completion_policy="require_start_or_dataless",
            file_only=True,
            include_size=True,
        ),
        TransitionSpec(
            state_attr="delete_state",
            start_label="deleting",
            end_label="deleted",
            start_getter="_path_for_delete_start",
            end_getter="_path_for_delete_end",
            file_only=True,
            include_size=True,
        ),
        TransitionSpec(
            state_attr="dir_create_state",
            start_label="creating-dir",
            end_label="created-dir",
            start_getter="_path_for_dir_create_start",
            end_getter="_path_for_dir_create_end",
        ),
        TransitionSpec(
            state_attr="dir_delete_state",
            start_label="deleting-dir",
            end_label="deleted-dir",
            start_getter="_path_for_dir_delete_start",
            end_getter="_path_for_dir_delete_end",
        ),
    )

    def build_maps(self, lines: Iterable[str]) -> None:
        for line in lines:
            self._observe_line(line)

    def emit_events(self, lines: Iterable[str]) -> list[str]:
        output: list[str] = []
        for line in lines:
            output.extend(self.feed_line(line))
        return output

    def feed_line(self, line: str) -> list[str]:
        self._observe_line(line)

        output: list[str] = []
        for spec in self.TRANSITIONS:
            self._handle_transition(line, output, spec)

        path_change_event = self._path_change_event(line)
        if path_change_event is not None:
            output.append(path_change_event)
        return output

    def _observe_line(self, line: str) -> None:
        self._capture_local_items(line)
        self._capture_provider_links(line)
        self._capture_known_sizes(line)

    def _capture_local_items(self, line: str) -> None:
        for doc_id, parent_id, masked_name in DOC_ITEM_RE.findall(line):
            resolved = self._resolve_doc_path(parent_id, masked_name, line)
            if resolved is not None:
                self.doc_paths.setdefault(doc_id, resolved)

        inode_path = self._path_from_item_inode(line)
        if inode_path is not None:
            for doc_id in DOC_ID_RE.findall(line):
                self.doc_paths.setdefault(doc_id, inode_path)

        for file_id, _, _ in DIR_ITEM_RE.findall(line):
            resolved = self.resolver.local_dir_path(file_id)
            if resolved is not None:
                self.provider_paths.setdefault(file_id, resolved)

    def _capture_provider_links(self, line: str) -> None:
        for kind, ident, provider_id in RECONCILE_RE.findall(line):
            path = self.doc_paths.get(ident) if kind == "docID" else self.resolver.local_dir_path(ident)
            if path is not None:
                self.provider_paths.setdefault(provider_id, path)

        for doc_id, provider_id in PROP_DOC_TARGET_RE.findall(line):
            path = self.doc_paths.get(doc_id)
            if path is not None:
                self.provider_paths.setdefault(provider_id, path)

        for doc_id, provider_id in PROP_DOC_ACTUAL_RE.findall(line):
            path = self.doc_paths.get(doc_id)
            if path is not None:
                self.provider_paths.setdefault(provider_id, path)

        for file_id, provider_id in PROP_FILE_TARGET_RE.findall(line):
            path = self.resolver.local_dir_path(file_id)
            if path is not None:
                self.provider_paths.setdefault(provider_id, path)

        for provider_id, parent_provider_id, masked_name in PROVIDER_ITEM_RE.findall(line):
            parent = self.provider_paths.get(parent_provider_id)
            if parent is None:
                continue
            resolved = self.resolver.resolve_child(parent, masked_name)
            if resolved is not None:
                self.provider_paths.setdefault(provider_id, resolved)

    def _capture_known_sizes(self, line: str) -> None:
        size = self._latest_size(line)
        if size is None:
            return

        for path in self._paths_for_doc_ids(line):
            self.path_sizes[path] = size

        provider_path = self._path_for_provider_context(line)
        if provider_path is not None:
            self.path_sizes[provider_path] = size

    def _handle_transition(self, line: str, output: list[str], spec: TransitionSpec) -> None:
        self._handle_transition_start(line, output, spec)
        self._handle_transition_end(line, output, spec)

    def _handle_transition_start(self, line: str, output: list[str], spec: TransitionSpec) -> None:
        if spec.start_label is None or spec.start_getter is None:
            return

        path = getattr(self, spec.start_getter)(line)
        if not self._matches_scope(path, file_only=spec.file_only):
            return

        state_map = getattr(self, spec.state_attr)
        if state_map.get(path) == spec.start_label:
            return

        size = self._size_for_path(path, line) if spec.include_size else None
        if self.verbose:
            output.append(self._format_verbose_event(spec.start_label, path, line, size=size))
        state_map[path] = spec.start_label

    def _handle_transition_end(self, line: str, output: list[str], spec: TransitionSpec) -> None:
        path = getattr(self, spec.end_getter)(line)
        if not self._matches_scope(path, file_only=spec.file_only):
            return

        state_map = getattr(self, spec.state_attr)
        current_state = state_map.get(path)
        if current_state == spec.end_label or not self._completion_allowed(spec, current_state, line):
            return

        size = self._size_for_path(path, line) if spec.include_size else None
        output.append(self._format_event(spec.end_label, path, size=size))
        state_map[path] = spec.end_label

    def _completion_allowed(self, spec: TransitionSpec, current_state: str | None, line: str) -> bool:
        if spec.completion_policy == "require_start":
            return current_state == spec.start_label
        if spec.completion_policy == "require_start_or_dataless":
            return current_state == spec.start_label or "diffs:dataless" in line
        return True

    def _matches_scope(self, path: Path | None, *, file_only: bool) -> bool:
        if path is None:
            return False
        return not file_only or not path.is_dir()

    def _format_event(self, label: str, path: Path, *, size: int | None = None) -> str:
        details = self._event_details(path, size=size)
        if not details:
            return f"{label} {path}"
        return f"{label} {path} ({'; '.join(details)})"

    def _format_verbose_event(self, label: str, path: Path, line: str, *, size: int | None = None) -> str:
        details = self._event_details(path, size=size, include_decode_reason=True)

        delete_match = DELETE_START_RE.search(line)
        if delete_match:
            details.append(f"trigger: delete:{delete_match.group(2)}")

        diffs_match = DIFFS_RE.search(line)
        if diffs_match:
            details.append(f"trigger: {diffs_match.group(1)}")

        why_match = WHY_RE.search(line)
        if why_match:
            details.append(f"why: {why_match.group(1)}")

        if not details:
            return f"{label} {path}"
        return f"{label} {path} ({'; '.join(details)})"

    def _event_details(
        self,
        path: Path,
        *,
        size: int | None = None,
        include_decode_reason: bool | None = None,
    ) -> list[str]:
        details: list[str] = []
        if size is not None:
            details.append(f"fsize: {size}")

        should_include_decode = self.verbose if include_decode_reason is None else include_decode_reason
        if should_include_decode:
            decode_reason = self.path_decode_failures.get(path)
            if decode_reason is not None:
                details.append(f"decode: {decode_reason}")
        return details

    def _size_for_path(self, path: Path, line: str) -> int | None:
        size = self._latest_size(line)
        if size is not None:
            self.path_sizes[path] = size
            return size
        return self.path_sizes.get(path)

    def _latest_size(self, line: str) -> int | None:
        sizes = [int(match) for match in SIZE_RE.findall(line)]
        if not sizes:
            return None
        return sizes[-1]

    def _paths_for_doc_ids(self, line: str) -> list[Path]:
        return [path for doc_id in DOC_ID_RE.findall(line) if (path := self.doc_paths.get(doc_id)) is not None]

    def _path_for_provider_context(self, line: str) -> Path | None:
        fp_match = FP_ITEM_RE.search(line)
        if fp_match:
            path = self.provider_paths.get(fp_match.group(1))
            if path is not None:
                return path

        provider_match = PROVIDER_DOC_RE.search(line)
        if provider_match:
            path = self.provider_paths.get(provider_match.group(1))
            if path is not None:
                return path
        return None

    def _resolve_doc_path(self, parent_file_id: str, masked_name: str, line: str) -> Path | None:
        resolved = self.resolver.resolve_doc_path(parent_file_id, masked_name)
        if resolved is not None:
            self.path_decode_failures.pop(resolved, None)
            return resolved

        ino_path = self._path_from_item_inode(line)
        if ino_path is not None:
            self.path_decode_failures.pop(ino_path, None)
            return ino_path

        masked_path = self.resolver.masked_child_path(parent_file_id, masked_name)
        if masked_path is None:
            return None

        decode_reason = self.resolver.child_resolution_reason(masked_path.parent, masked_name)
        if decode_reason is not None:
            self.path_decode_failures[masked_path] = decode_reason
        return masked_path

    def _path_from_item_inode(self, line: str) -> Path | None:
        for inode in FILE_INO_RE.findall(line):
            path = self.resolver.local_path(inode)
            if path is not None:
                return path
        return None

    def _path_for_upload_state(self, line: str, state: str) -> Path | None:
        if f"ul:{state}" not in line:
            return None

        paths = self._paths_for_doc_ids(line)
        if paths:
            return paths[0]
        return self._path_for_provider_context(line)

    def _path_for_uploading(self, line: str) -> Path | None:
        return self._path_for_upload_state(line, "uploading")

    def _path_for_uploaded(self, line: str) -> Path | None:
        return self._path_for_upload_state(line, "uploaded")

    def _path_for_downloading(self, line: str) -> Path | None:
        match = FP_FETCH_RE.search(line)
        if not match:
            return None
        return self.provider_paths.get(match.group(1))

    def _path_for_downloaded(self, line: str) -> Path | None:
        match = DOWNLOAD_END_RE.search(line)
        if not match:
            return None
        return self.doc_paths.get(match.group(1))

    def _path_for_delete_start(self, line: str) -> Path | None:
        match = DELETE_START_RE.search(line)
        if not match:
            return None
        return self.doc_paths.get(match.group(1))

    def _path_for_delete_end(self, line: str) -> Path | None:
        match = DELETE_END_RE.search(line)
        if not match:
            return None
        return self.doc_paths.get(match.group(1))

    def _path_for_dir_create_start(self, line: str) -> Path | None:
        match = DIR_CREATE_START_RE.search(line)
        if not match:
            return None
        return self._dir_path_for_file_id(match.group(1))

    def _path_for_dir_create_end(self, line: str) -> Path | None:
        match = DIR_CREATE_END_RE.search(line)
        if not match:
            return None
        return self._dir_path_for_file_id(match.group(1))

    def _path_for_dir_delete_start(self, line: str) -> Path | None:
        match = DIR_DELETE_START_RE.search(line)
        if not match:
            return None
        return self._dir_path_for_file_id(match.group(1))

    def _path_for_dir_delete_end(self, line: str) -> Path | None:
        match = DIR_DELETE_END_RE.search(line)
        if not match:
            return None
        return self._dir_path_for_file_id(match.group(1))

    def _dir_path_for_file_id(self, file_id: str) -> Path | None:
        path = self.provider_paths.get(file_id)
        if path is not None:
            return path
        return self.resolver.local_dir_path(file_id)

    def _path_change_event(self, line: str) -> str | None:
        doc_event = self._doc_path_change_event(line)
        if doc_event is not None:
            return doc_event
        return self._dir_path_change_event(line)

    def _doc_path_change_event(self, line: str) -> str | None:
        match = DOC_PATH_UPDATE_RE.search(line)
        if not match:
            return None

        doc_id, _, _, new_parent_id, new_name, diffs = match.groups()
        old_path = self.doc_paths.get(doc_id)
        new_path = self._resolve_doc_path(new_parent_id, new_name, line)
        if new_path is not None:
            self.doc_paths[doc_id] = new_path
        return self._format_path_change_event(
            old_path=old_path,
            new_path=new_path,
            diffs=diffs,
            rename_label="renamed",
            move_label="moved",
        )

    def _dir_path_change_event(self, line: str) -> str | None:
        completion_event = self._dir_update_completion_event(line)
        if completion_event is not None:
            return completion_event

        snapshot_event = self._dir_snapshot_change_event(line)
        if snapshot_event is not None:
            return snapshot_event

        match = DIR_PATH_UPDATE_RE.search(line)
        if not match:
            return None

        file_id, _, _, _, _, diffs = match.groups()
        old_path = self.provider_paths.get(file_id)
        new_path = self.resolver.local_dir_path(file_id)
        if new_path is not None:
            self.provider_paths[file_id] = new_path
        return self._format_path_change_event(
            old_path=old_path,
            new_path=new_path,
            diffs=diffs,
            rename_label="renamed-dir",
            move_label="moved-dir",
        )

    def _dir_update_completion_event(self, line: str) -> str | None:
        match = DIR_UPDATE_COMPLETION_RE.search(line)
        if not match:
            return None

        file_id, parent_ref, _, diffs = match.groups()
        old_path = self.provider_paths.get(file_id)
        new_path = self.resolver.local_path(file_id)
        if new_path is not None:
            self.provider_paths[file_id] = new_path

        normalized_diffs = {part for part in diffs.replace(" ", "").split("|") if part}
        if old_path is None:
            return None
        if parent_ref in {"trash", ".trash"} and "parentID" in normalized_diffs:
            return f"deleted-dir {old_path}"
        return self._format_path_change_event(
            old_path=old_path,
            new_path=new_path,
            diffs=diffs,
            rename_label="renamed-dir",
            move_label="moved-dir",
        )

    def _dir_snapshot_change_event(self, line: str) -> str | None:
        match = DIR_SNAPSHOT_CHANGE_RE.search(line)
        if not match:
            return None

        file_id, parent_ref, _, diffs = match.groups()
        old_path = self.provider_paths.get(file_id)
        new_path = self.resolver.local_path(file_id)
        if new_path is not None:
            self.provider_paths[file_id] = new_path

        normalized_diffs = {part for part in diffs.replace(" ", "").split("|") if part}
        if old_path is None:
            return None
        if parent_ref in {"trash", ".trash"} and "parentID" in normalized_diffs:
            return f"deleted-dir {old_path}"
        return self._format_path_change_event(
            old_path=old_path,
            new_path=new_path,
            diffs=diffs,
            rename_label="renamed-dir",
            move_label="moved-dir",
        )

    def _format_path_change_event(
        self,
        *,
        old_path: Path | None,
        new_path: Path | None,
        diffs: str,
        rename_label: str,
        move_label: str,
    ) -> str | None:
        if old_path is None or new_path is None or old_path == new_path:
            return None

        normalized_diffs = {part for part in diffs.replace(" ", "").split("|") if part}
        if "parentID" in normalized_diffs:
            return f"{move_label} {old_path} -> {new_path}"
        if "filename" in normalized_diffs:
            return f"{rename_label} {old_path} -> {new_path}"
        return None


def parse_lines(lines: list[str], volume_path: Path | None = None, verbose: bool = False) -> list[str]:
    resolver = Resolver(volume_path=volume_path or Path.cwd())
    parser = ActivityParser(resolver=resolver, verbose=verbose)
    parser.build_maps(lines)
    return parser.emit_events(lines)
