"""Packs the Super Admin panel (built dist + sources + Firestore rules + docs) into releases/dt-food-admin-panel.zip.

Run `npm run build` in admin/ first.  python3 -I tool/make_panel_zip.py
"""
import os
import zipfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
TOP = 'dt-food-admin-panel'
FILES = ['.firebaserc', 'firebase.json', 'docs/FIREBASE_SETUP.md', 'docs/USER_GUIDE.md', 'docs/QA_REPORT.md', 'firebase/firestore.rules', 'firebase/firestore.indexes.json', 'firebase/package.json',
         'admin/.gitignore', 'admin/index.html', 'admin/package.json', 'admin/package-lock.json', 'admin/tsconfig.json', 'admin/vite.config.ts']
DIRS = ['admin/src', 'admin/public', 'admin/dist', 'firebase/test']
SKIP = {'node_modules', '.DS_Store', 'firestore-debug.log'}


def main():
    out = os.path.join(ROOT, 'releases', 'dt-food-admin-panel.zip')
    if not os.path.isdir(os.path.join(ROOT, 'admin', 'dist')):
        raise SystemExit('admin/dist is missing: run npm run build in admin/ first')
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        z.write(os.path.join(ROOT, 'tool', 'README-DEPLOY.txt'), f'{TOP}/README-DEPLOY.txt')
        for f in FILES:
            p = os.path.join(ROOT, f)
            if os.path.exists(p):
                z.write(p, f'{TOP}/{f}')
        for d in DIRS:
            for base, dirs, names in os.walk(os.path.join(ROOT, d)):
                dirs[:] = [x for x in dirs if x not in SKIP]
                for n in names:
                    if n in SKIP:
                        continue
                    p = os.path.join(base, n)
                    z.write(p, f'{TOP}/{os.path.relpath(p, ROOT)}')
    print('wrote', out, os.path.getsize(out), 'bytes')


main()
