"""Extract the tab bar's measured material verbatim; no keyboard history used."""
from pathlib import Path
import hashlib, json, re
root = Path(__file__).resolve().parents[1]
upstream = root / 'reference/Theseus'
source = upstream / 'Sources/Theseus/Components/TheseusTabBar.swift'
text = source.read_text()
start = text.index('    struct ChromeCurve {')
end = text.index('    static func iOS26Chrome(', start)
chunk = text[start:end]
# Drop unrelated lens / selection / iOS26 material declarations.
chunk = '\n'.join(line for line in chunk.splitlines()
                  if not re.match(r'    static let (iOS26|iOS27Pill)', line))
chunk = chunk.replace('static func iOS27Chrome(', 'static func material(')
result = ('// Extracted from TheseusTabBar.swift; Apache-2.0, Vadim Drobinin.\n'
          '// Only background material. No tab items / selected pill / lens.\n'
          'import UIKit\n\ninternal enum NTKTabBarChrome {\n' + chunk + '\n'
          '    static let chromeChromaDark: CGFloat = 1.12\n}\n')
assert 'TheseusMaterialModel.bodyValue' in result
assert 'PillMaterial' not in result
out = root / 'src/NTKTabBarChrome.swift'
out.write_text(result)
manifest = {'upstream_commit': '71ca1c127a4e7fe3387361f160c4890dbd427f66',
            'reference_url': 'https://github.com/valzevul/Theseus/blob/master/assets/tabBar.gif',
            'upstream_file': str(source.relative_to(root)),
            'upstream_file_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'adapter_file': str(out.relative_to(root)),
            'adapter_sha256': hashlib.sha256(out.read_bytes()).hexdigest(),
            'compiled': False, 'runtime_verified': False}
(root / 'material-provenance.json').write_text(json.dumps(manifest, indent=2)+'\n')
print(json.dumps(manifest, indent=2))
