#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ort-vtable-offsets.py — 从 onnxruntime_c_api.h 生成 OrtApi 函数指针表的偏移

背景：
    官方 / pip 的 onnxruntime.dll 只导出 OrtGetApiBase 等极少数符号，
    其余几百个 C API 全部位于 OrtApi 结构体（一堆函数指针）里。
    极语言没有 C 编译器可用，于是需要这个偏移表：
        OrtApiBase* 基 = OrtGetApiBase();
        GetApi = 基(0)$;                      // 第 0 个字段
        OrtApi* 接口 = GetApi(ORT_API_VERSION);
        函数指针 = 接口(偏移)$;                // 偏移 = index * 8（x64）

用法：
    python ort-vtable-offsets.py --header onnxruntime_c_api.h
    python ort-vtable-offsets.py --header onnxruntime_c_api.h --want CreateEnv,Run,CreateSessionFromArray
    python ort-vtable-offsets.py --header onnxruntime_c_api.h --ji          # 直接输出极语言 常量/注释 片段

注意：
    1) ORT_API_VERSION 必须与运行时的 dll 匹配，版本号取自同一个头文件的
       #define ORT_API_VERSION；请求过高的版本 GetApi 会返回 NULL 并打印
       "The requested API version [31] is not available, only API versions [1, 23] ..."。
    2) 该结构体只追加字段，所以低版本的偏移是高版本的前缀，不会漂移。
    3) 只解析 struct OrtApi 本体（注意别被前面的 struct OrtApiBase 骗了）。
"""
import argparse
import re
import sys

FALLBACK = {
    'CreateStatus': 0, 'GetErrorCode': 8, 'GetErrorMessage': 16, 'CreateEnv': 24,
    'CreateSession': 56, 'CreateSessionFromArray': 64, 'Run': 72, 'CreateSessionOptions': 80,
    'CreateTensorAsOrtValue': 384, 'CreateTensorWithDataAsOrtValue': 392,
    'GetTensorMutableData': 408, 'GetAllocatorWithDefaultOptions': 624,
    'SessionGetInputCount': 240, 'SessionGetOutputCount': 248,
    'SessionGetInputName': 288, 'SessionGetOutputName': 296, 'CreateRunOptions': 312,
}

COMMON = ['CreateEnv', 'CreateSessionFromArray', 'Run', 'CreateSessionOptions',
          'CreateTensorAsOrtValue', 'CreateTensorWithDataAsOrtValue', 'GetTensorMutableData',
          'GetAllocatorWithDefaultOptions', 'SessionGetInputCount', 'SessionGetOutputCount',
          'SessionGetInputName', 'SessionGetOutputName', 'GetDimensionsCount', 'GetDimensions',
          'GetTensorShapeElementCount', 'ReleaseValue', 'ReleaseSession', 'ReleaseEnv',
          'ReleaseStatus', 'ReleaseSessionOptions']


def parse(header_text):
    ver_match = re.search(r'#define\s+ORT_API_VERSION\s+(\d+)', header_text)
    ver = int(ver_match.group(1)) if ver_match else None

    start = header_text.index('struct OrtApi {')
    start = header_text.index('{', start)
    depth, j = 0, start
    while j < len(header_text):
        c = header_text[j]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                break
        j += 1
    body = header_text[start + 1:j]
    body = re.sub(r'/\*.*?\*/', '', body, flags=re.S)
    body = re.sub(r'//[^\n]*', '', body)

    fields = []
    for line in body.split('\n'):
        s = line.strip()
        if not s or s.startswith('#'):       # 该结构体内部实测没有影响布局的条件编译
            continue
        m = re.search(r'ORT_API2_STATUS\(\s*(\w+)', s)
        if m:
            fields.append(m.group(1))
            continue
        m = re.search(r'ORT_CLASS_RELEASE\(\s*(\w+)', s)
        if m:
            fields.append('Release' + m.group(1))
            continue
        m = re.search(r'ORT_API_CALL\s*\*\s*(\w+)\s*\)', s)
        if m:
            fields.append(m.group(1))
    return ver, fields


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--header', help='onnxruntime_c_api.h 路径；省略则只用内置常用偏移表')
    ap.add_argument('--want', default=','.join(COMMON), help='逗号分隔，只看这些函数')
    ap.add_argument('--all', action='store_true', help='打印全部字段')
    ap.add_argument('--ji', action='store_true', help='额外输出极语言可直接粘贴的常量定义')
    args = ap.parse_args()

    if not args.header:
        print('# 未提供头文件，使用内置常用偏移（onnxruntime 1.23.x / ORT_API_VERSION=23）')
        for k, v in FALLBACK.items():
            print(f'{k:38s} index={v // 8:3d} offset={v}')
        return 0

    text = open(args.header, encoding='utf-8', errors='replace').read()
    ver, fields = parse(text)
    print(f'# header = {args.header}')
    print(f'# ORT_API_VERSION = {ver}   OrtApi 字段总数 = {len(fields)}')
    print(f'# 极语言取函数指针： 大数 fn = 接口(偏移)$;   （偏移 = 序号 * 8）')
    print(f'{"function":40s} {"index":>5s} {"offset":>7s}')

    if args.all:
        names = fields
    else:
        names = [w.strip() for w in args.want.split(',') if w.strip()]
    index_of = {n: i for i, n in enumerate(fields)}
    for n in names:
        if n in index_of:
            i = index_of[n]
            print(f'{n:40s} {i:5d} {i * 8:7d}')
        else:
            print(f'{n:40s} {"-":>5s} {"-":>7s}   # 该版本没有这个 API')

    if args.ji:
        print('\n// ===== 粘贴到极语言源码里（x64）=====')
        for n in names:
            if n in index_of:
                print(f'// {n:36s} 接口({index_of[n] * 8})$')
    return 0


if __name__ == '__main__':
    sys.exit(main())
