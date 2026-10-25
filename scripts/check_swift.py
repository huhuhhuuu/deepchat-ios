#!/usr/bin/env python3
"""在 Windows 上没有 Swift 编译器的前提下，做力所能及的静态检查：
1. 括号 / 大括号 / 方括号是否配平（忽略字符串、注释、字符字面量）
2. 字符串是否闭合（含三引号多行字符串）
3. Info.plist / Contents.json 是否能被正确解析
4. 一些已知容易写错的模式检查
"""
import json
import os
import plistlib
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "DeepChat")

problems = []
checked = 0


def strip_code(text):
    """去掉注释与字符串内容，保留换行，方便做括号配平"""
    out = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]

        # 多行字符串 """
        if text.startswith('"""', i):
            j = i + 3
            while j < n and not text.startswith('"""', j):
                j += 1
            if j >= n:
                problems.append("多行字符串未闭合")
                return "".join(out)
            out.append("\n" * text[i:j].count("\n"))
            i = j + 3
            continue

        # 行注释
        if text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue

        # 块注释
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            if j < 0:
                problems.append("块注释未闭合")
                return "".join(out)
            out.append("\n" * text[i:j].count("\n"))
            i = j + 2
            continue

        # 字符串
        if ch == '"':
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == '"':
                    break
                j += 1
            if j >= n:
                problems.append("字符串未闭合")
                return "".join(out)
            out.append('""')
            i = j + 1
            continue

        out.append(ch)
        i += 1
    return "".join(out)


def check_balance(path, code):
    pairs = {"}": "{", ")": "(", "]": "["}
    stack = []
    line = 1
    for ch in code:
        if ch == "\n":
            line += 1
            continue
        if ch in "{([":
            stack.append((ch, line))
        elif ch in "})]":
            if not stack:
                problems.append("%s:%d 多余的 %s" % (path, line, ch))
                return
            open_ch, open_line = stack.pop()
            if pairs[ch] != open_ch:
                problems.append("%s:%d %s 与第 %d 行的 %s 不匹配" % (path, line, ch, open_line, open_ch))
                return
    if stack:
        open_ch, open_line = stack[-1]
        problems.append("%s:%d 未闭合的 %s" % (path, open_line, open_ch))


def check_patterns(path, text):
    bad_patterns = [
        (r"\\\.element\b", "元组元素 key path (\\\\.element) 可能无法编译，改用索引"),
        (r"\\\.offset\b", "元组元素 key path (\\\\.offset) 可能无法编译，改用索引"),
        (r"ForEach\(Array\([^)]*enumerated\(\)\)", "建议改用 indices 遍历，避免元组 key path"),
    ]
    for pattern, message in bad_patterns:
        if re.search(pattern, text):
            problems.append("%s: %s" % (path, message))


def walk():
    global checked
    for dirpath, dirnames, filenames in os.walk(SRC):
        dirnames.sort()
        for name in sorted(filenames):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, ROOT)
            if name.endswith(".swift"):
                with open(full, encoding="utf-8") as f:
                    text = f.read()
                stripped = strip_code(text)
                check_balance(rel, stripped)
                check_patterns(rel, text)
                checked += 1
            elif name == "Info.plist":
                with open(full, "rb") as f:
                    plistlib.load(f)
            elif name == "Contents.json":
                with open(full, encoding="utf-8") as f:
                    json.load(f)


def main():
    walk()
    print("已检查 %d 个 Swift 文件" % checked)
    if problems:
        print("\n发现 %d 个问题：" % len(problems))
        for p in problems:
            print("  - " + p)
        return 1
    print("括号配平、字符串闭合、plist/json 解析：全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
