# Quick local lint for common Godot 4 GDScript static-typing pitfalls.
import re, sys, glob
GENERIC = r'(?<![\w.])(abs|sign|floor|ceil|round|clamp|lerp|min|max|snapped|wrap|pow_)\s*\('
bad = 0
for f in sorted(glob.glob('scripts/*.gd')):
    for n, line in enumerate(open(f), 1):
        code = line.split('#')[0]
        rhs = code.split(':=', 1)[1] if ':=' in code else ''
        if rhs and re.search(GENERIC, re.sub(r'\b(int|float)\((?:[^()]|\([^()]*\))*\)', 'X', rhs)):
            print(f"{f}:{n}: ':=' with Variant-returning generic fn -> {code.strip()}"); bad += 1
        if 'vec' not in code and re.search(r'\?\s*[^:]+\s:\s', code) and '"' not in code and "'" not in code:
            print(f"{f}:{n}: C-style ternary? -> {code.strip()}"); bad += 1
sys.exit(1 if bad else 0)
