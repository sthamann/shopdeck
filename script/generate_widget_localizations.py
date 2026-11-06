#!/usr/bin/env python3
import pathlib,json
root=pathlib.Path(__file__).resolve().parent.parent
rows=[r.split('\t') for r in (root/'Sources/Shopdeck/Resources/Localizations.tsv').read_text().splitlines() if len(r.split('\t'))==6]
for index,locale in enumerate(['de','en','nl','es','fr','it']):
    path=root/'Widgets/Resources'/f'{locale}.lproj'/'Localizable.strings';path.parent.mkdir(parents=True,exist_ok=True)
    values={row[0]:row[index] for row in rows}
    path.write_text('\n'.join(json.dumps(k,ensure_ascii=False)+' = '+json.dumps(v,ensure_ascii=False)+';' for k,v in sorted(values.items()))+'\n')
