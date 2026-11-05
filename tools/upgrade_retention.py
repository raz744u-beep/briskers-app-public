#!/usr/bin/env python3
"""Synthetic release evidence only; never reads a shop device or remote service."""
import argparse
import json
import sqlite3
import xml.etree.ElementTree as ET
from pathlib import Path


def snapshot(path):
    with sqlite3.connect(f'file:{Path(path).resolve()}?mode=ro', uri=True) as db:
        assert db.execute('PRAGMA integrity_check').fetchall() == [('ok',)]
        tables = [r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")]
        return {t: sorted([list(row) for row in db.execute('SELECT * FROM "' + t.replace('"', '""') + '"')], key=repr) for t in tables}


def preferences(path):
    root = ET.parse(path).getroot()
    return {node.attrib['name']: (node.tag, node.text, node.attrib.get('value')) for node in root}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['prefs', 'snapshot', 'verify'])
    parser.add_argument('source')
    parser.add_argument('target')
    parser.add_argument('--prefs')
    parser.add_argument('--expected-prefs')
    args = parser.parse_args()
    if args.action == 'prefs':
        root = ET.Element('map')
        for key, value in json.loads(Path(args.source).read_text()).items():
            assert isinstance(value, str), 'Only production string preferences in fixture'
            ET.SubElement(root, 'string', name='flutter.' + key).text = value
        ET.ElementTree(root).write(args.target, encoding='utf-8', xml_declaration=True)
    elif args.action == 'snapshot':
        Path(args.target).write_text(json.dumps(snapshot(args.source), sort_keys=True, indent=2))
    else:
        expected = json.loads(Path(args.source).read_text())
        actual = snapshot(args.target)
        for table, rows in expected.items():
            assert table in actual, f'Missing table {table}'
            assert rows == actual[table], f'Changed/duplicated rows in {table}'
        if args.prefs:
            expected_prefs = preferences(args.expected_prefs)
            actual_prefs = preferences(args.prefs)
            for key, value in expected_prefs.items():
                assert actual_prefs.get(key) == value, f'Changed preference {key}'
            assert actual_prefs['flutter.briskers_connection_mode'][1] == 'offline'
        print(json.dumps({'integrity_check': 'ok', 'retained_tables': len(expected),
                          'retained_rows': {k: len(v) for k, v in expected.items() if v},
                          'preferences_preserved': bool(args.prefs), 'force_offline': bool(args.prefs)}, sort_keys=True))


if __name__ == '__main__':
    main()
