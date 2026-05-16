#!/usr/bin/env python3
"""Patch Codex's bundled main process to expose Linux open-in targets.

The upstream macOS app ships open-target definitions for macOS/Windows only.
On Linux that leaves only the hidden system default target, so the toolbar
caret renders an empty menu. This patch injects Linux target definitions for
common installed editors and a file-manager fallback.
"""
from __future__ import annotations

import pathlib
import sys

MARKER = "Codex-App-Omarchy linux-open-targets patch"
ANCHOR_V1 = (
    "var Ed=Td(process.platform),Dd=Id(Ed),Od=new Set(Ed.filter(e=>e.kind===`editor`).map(e=>e.id)),kd=null,Ad=null;"
)
REPLACEMENT_V1 = (
    "/* Codex-App-Omarchy linux-open-targets patch */"
    "function __codexOmarchyLinuxOpenTargets(x){"
    "let t=x.slice(),n=new Set(t.map(e=>e.id)),r=e=>{for(let t of e){let e=U(t);if(e)return e}return null},"
    "i=(e,i,a,o,s,c,l)=>{n.has(e)||(t.push({id:e,label:i,icon:a,kind:o,detect:()=>r(s),args:c,supportsSsh:l}),n.add(e))},"
    "a=(e,t,n,r,a,o)=>i(e,t,n,`editor`,r,a,o),"
    "o=(e,t,n,r)=>a(e,t,n,r,Vu,!1);"
    "function s(t,n,r,i,a){return r!=null&&e.Ct(r)&&(i!=null||a!=null)?Cl({hostConfig:r,location:n,remotePath:a,remoteWorkspaceRoot:i}):n?[`--goto`,`${t}:${n.line}:${n.column}`]:[t]}"
    "let c=[`alacritty`,`ghostty`,`kitty`,`wezterm`,`foot`,`gnome-terminal`,`konsole`,`xterm`],l=()=>r(c),u=(e,t,n,r)=>{let i=r?[`+call cursor(${r.line},${r.column})`,n]:[n],a=e.split(/[\\/]/).pop();return a===`wezterm`?[`start`,`--`,t,...i]:a===`gnome-terminal`?[`--`,t,...i]:[`-e`,t,...i]},d=(e,a,o)=>{n.has(e)||(t.push({id:e,label:a,icon:`apps/vscode.png`,kind:`editor`,detect:()=>{let e=r(o);return e&&l()?e:null},open:async({command:e,path:t,location:n})=>{let r=l();if(!r)throw Error(`No terminal emulator is available for terminal editor target`);await ol(r,u(r,e,t,n))}}),n.add(e))};"
    "a(`vscode`,`VS Code`,`apps/vscode.png`,[`code`],s,!0);"
    "a(`vscodeInsiders`,`VS Code Insiders`,`apps/vscode-insiders.png`,[`code-insiders`],s,!0);"
    "a(`vscodium`,`VSCodium`,`apps/vscode.png`,[`codium`],s,!0);"
    "a(`cursor`,`Cursor`,`apps/cursor.png`,[`cursor`],s,!0);"
    "a(`windsurf`,`Windsurf`,`apps/windsurf.png`,[`windsurf`],s,!0);"
    "a(`antigravity`,`Antigravity`,`apps/antigravity.png`,[`antigravity`],s,!0);"
    "a(`zed`,`Zed`,`apps/zed.png`,[`zed`,`zeditor`],Hu,!1);"
    "a(`sublimeText`,`Sublime Text`,`apps/sublime-text.png`,[`subl`,`sublime_text`],Hu,!1);"
    "o(`androidStudio`,`Android Studio`,`apps/android-studio.png`,[`studio`,`android-studio`]);"
    "o(`intellij`,`IntelliJ IDEA`,`apps/intellij.png`,[`idea`,`intellij-idea-ultimate`,`intellij-idea-community`]);"
    "o(`rider`,`Rider`,`apps/rider.png`,[`rider`]);"
    "o(`goland`,`GoLand`,`apps/goland.png`,[`goland`]);"
    "o(`rustrover`,`RustRover`,`apps/rustrover.png`,[`rustrover`]);"
    "o(`pycharm`,`PyCharm`,`apps/pycharm.png`,[`pycharm`]);"
    "o(`webstorm`,`WebStorm`,`apps/webstorm.svg`,[`webstorm`]);"
    "o(`phpstorm`,`PhpStorm`,`apps/phpstorm.png`,[`phpstorm`]);"
    "a(`kate`,`Kate`,`apps/vscode.png`,[`kate`],Hu,!1);"
    "a(`geany`,`Geany`,`apps/vscode.png`,[`geany`],Hu,!1);"
    "a(`gnomeTextEditor`,`GNOME Text Editor`,`apps/vscode.png`,[`gnome-text-editor`,`gedit`],Hu,!1);"
    "a(`emacs`,`Emacs`,`apps/vscode.png`,[`emacs`],Hu,!1);"
    "d(`neovim`,`Neovim`,[`nvim`]);"
    "d(`vim`,`Vim`,[`vim`]);"
    "d(`helix`,`Helix`,[`hx`,`helix`]);"
    "n.has(`fileManager`)||(t.push({id:`fileManager`,label:`File Manager`,icon:`apps/file-explorer.png`,kind:`fileManager`,detect:()=>r([`xdg-open`,`nautilus`,`dolphin`,`thunar`,`nemo`,`pcmanfm`]),args:il}),n.add(`fileManager`));"
    "return t}"
    "var Ed=process.platform===`linux`?__codexOmarchyLinuxOpenTargets(Td(process.platform)):Td(process.platform),Dd=Id(Ed),Od=new Set(Ed.filter(e=>e.kind===`editor`).map(e=>e.id)),kd=null,Ad=null;"
)
ANCHOR_V2 = (
    "var vE=_E(process.platform),yE=OE(vE),bE=new Set(vE.filter(e=>e.kind===`editor`).map(e=>e.id)),xE=null,SE=null;"
)
REPLACEMENT_V2 = (
    "/* Codex-App-Omarchy linux-open-targets patch */"
    "function __codexOmarchyLinuxOpenTargets(x){"
    "if(process.platform!==`linux`)return x;"
    "let t=x.slice(),n=new Set(t.map(e=>e.id)),r=e=>{for(let t of e){let e=lm(t);if(e)return e}return null},"
    "a=(e,i,a,o,s=ww,c=!0)=>{n.has(e)||(t.push({id:e,label:i,icon:a,kind:`editor`,detect:()=>r(o),args:s,supportsSsh:c}),n.add(e))},"
    "o=(e,t,n,r)=>a(e,t,n,r,PT,!1),"
    "s=(e,t,n,r)=>a(e,t,n,r,NT,!1);"
    "function c(t,n,r,i){let a=i?[`+call cursor(${i.line},${i.column})`,r]:[r],o=t.split(/[\\/]/).pop();return o===`wezterm`?[`start`,`--`,n,...a]:o===`gnome-terminal`?[`--`,n,...a]:[`-e`,n,...a]}"
    "let l=[`alacritty`,`ghostty`,`kitty`,`wezterm`,`foot`,`gnome-terminal`,`konsole`,`xterm`],u=()=>r(l),d=(e,i,a)=>{n.has(e)||(t.push({id:e,label:i,icon:`apps/vscode.png`,kind:`editor`,detect:()=>{let e=r(a);return e&&u()?e:null},open:async({command:e,path:t,location:n})=>{let r=u();if(!r)throw Error(`No terminal emulator is available for terminal editor target`);await pm(r,c(r,e,t,n))}}),n.add(e))};"
    "a(`vscode`,`VS Code`,`apps/vscode.png`,[`code`]);"
    "a(`vscodeInsiders`,`VS Code Insiders`,`apps/vscode-insiders.png`,[`code-insiders`]);"
    "a(`vscodium`,`VSCodium`,`apps/vscode.png`,[`codium`]);"
    "a(`cursor`,`Cursor`,`apps/cursor.png`,[`cursor`]);"
    "a(`windsurf`,`Windsurf`,`apps/windsurf.png`,[`windsurf`]);"
    "a(`antigravity`,`Antigravity`,`apps/antigravity.png`,[`antigravity`]);"
    "a(`zed`,`Zed`,`apps/zed.png`,[`zed`,`zeditor`],PT,!1);"
    "o(`sublimeText`,`Sublime Text`,`apps/sublime-text.png`,[`subl`,`sublime_text`]);"
    "s(`androidStudio`,`Android Studio`,`apps/android-studio.png`,[`studio`,`android-studio`]);"
    "s(`intellij`,`IntelliJ IDEA`,`apps/intellij.png`,[`idea`,`intellij-idea-ultimate`,`intellij-idea-community`]);"
    "s(`rider`,`Rider`,`apps/rider.png`,[`rider`]);"
    "s(`goland`,`GoLand`,`apps/goland.png`,[`goland`]);"
    "s(`rustrover`,`RustRover`,`apps/rustrover.png`,[`rustrover`]);"
    "s(`pycharm`,`PyCharm`,`apps/pycharm.png`,[`pycharm`]);"
    "s(`webstorm`,`WebStorm`,`apps/webstorm.svg`,[`webstorm`]);"
    "s(`phpstorm`,`PhpStorm`,`apps/phpstorm.png`,[`phpstorm`]);"
    "a(`kate`,`Kate`,`apps/vscode.png`,[`kate`],PT,!1);"
    "a(`geany`,`Geany`,`apps/vscode.png`,[`geany`],PT,!1);"
    "a(`gnomeTextEditor`,`GNOME Text Editor`,`apps/vscode.png`,[`gnome-text-editor`,`gedit`],PT,!1);"
    "a(`emacs`,`Emacs`,`apps/vscode.png`,[`emacs`],PT,!1);"
    "d(`neovim`,`Neovim`,[`nvim`]);"
    "d(`vim`,`Vim`,[`vim`]);"
    "d(`helix`,`Helix`,[`hx`,`helix`]);"
    "n.has(`fileManager`)||(t.push({id:`fileManager`,label:`File Manager`,icon:`apps/file-explorer.png`,kind:`fileManager`,detect:()=>r([`xdg-open`,`nautilus`,`dolphin`,`thunar`,`nemo`,`pcmanfm`]),args:e=>[e]}),n.add(`fileManager`));"
    "return t}"
    "var vE=__codexOmarchyLinuxOpenTargets(_E(process.platform)),yE=OE(vE),bE=new Set(vE.filter(e=>e.kind===`editor`).map(e=>e.id)),xE=null,SE=null;"
)

REPLACEMENTS = ((ANCHOR_V2, REPLACEMENT_V2), (ANCHOR_V1, REPLACEMENT_V1))


def find_main_bundles(app_asar: pathlib.Path) -> list[pathlib.Path]:
    build_dir = app_asar / ".vite" / "build"
    if not build_dir.is_dir():
        return []
    return sorted(build_dir.glob("main*.js"))


def replace_existing_patch(text: str) -> str | None:
    marker_start = text.find(f"/* {MARKER} */function __codexOmarchyLinuxOpenTargets")
    if marker_start < 0:
        return None
    replacement = REPLACEMENT_V2 if "var vE=" in text[marker_start : marker_start + 4000] else REPLACEMENT_V1
    for end_token in ("xE=null,SE=null;", "kd=null,Ad=null;"):
        marker_end = text.find(end_token, marker_start)
        if marker_end >= 0:
            marker_end += len(end_token)
            return text[:marker_start] + replacement + text[marker_end:]
    return None


def patch_bundle(bundle: pathlib.Path) -> str:
    text = bundle.read_text(encoding="utf-8")
    if MARKER in text:
        updated = replace_existing_patch(text)
        if updated is None:
            updated = text.replace(
                "function __codexOmarchyLinuxOpenTargets(e){let t=e.slice()",
                "function __codexOmarchyLinuxOpenTargets(x){let t=x.slice()",
                1,
            )
        if updated != text:
            bundle.write_text(updated, encoding="utf-8")
            return "updated"
        return "already patched"
    for anchor, replacement in REPLACEMENTS:
        if anchor in text:
            bundle.write_text(text.replace(anchor, replacement, 1), encoding="utf-8")
            return "patched"
    raise ValueError(f"open-target registry anchor was not found in {bundle}")


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("Usage: patch_codex_linux_open_targets.py /path/to/app_asar", file=sys.stderr)
        return 2

    app_asar = pathlib.Path(argv[1])
    bundles = find_main_bundles(app_asar)
    if not bundles:
        print(f"No Codex main bundle found under: {app_asar}")
        return 0

    patched = 0
    already = 0
    for bundle in bundles:
        result = patch_bundle(bundle)
        if result in {"patched", "updated"}:
            patched += 1
        elif result == "already patched":
            already += 1
        print(f"{bundle}: {result}")

    if patched == 0 and already == 0:
        print("No Codex main bundle was patched.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
