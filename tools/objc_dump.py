#!/usr/bin/env python3
"""Read ObjC class/method metadata from a decrypted thin arm64 Mach-O; never load it."""
import argparse, json, mmap, struct

def dump(path, class_filter=""):
    import re
    with open(path, 'rb') as f:
        m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
        def u32(o): return struct.unpack_from('<I', m, o)[0]
        def u64(o): return struct.unpack_from('<Q', m, o)[0]
        assert u32(0) == 0xfeedfacf, 'Expected thin little-endian Mach-O 64'
        segments, sections = [], {}
        o = 32
        for _ in range(u32(16)):
            cmd, size = u32(o), u32(o+4)
            if cmd == 0x19:
                v, vs, fo, fs = struct.unpack_from('<QQQQ', m, o+24)
                segments.append((v, v+vs, fo))
                for i in range(u32(o+64)):
                    p = o+72+80*i
                    name = m[p:p+16].split(b'\0')[0].decode()
                    sections[name] = (u64(p+32), u64(p+40), u32(p+48))
            o += size
        def offset(v):
            for lo, hi, fo in segments:
                if lo <= v < hi: return fo+v-lo
            raise ValueError(hex(v))
        def string(v):
            p = offset(v)
            end = m.find(b'\0', p, p+4096)
            if end < 0: raise ValueError('Unterminated string')
            return m[p:end].decode(errors='replace')
        def methods(v):
            if not v: return []
            p = offset(v); flags, count = u32(p), u32(p+4)
            small = bool(flags & 0x80000000); direct = bool(flags & 0x40000000)
            size = flags & 0xfffc
            if count > 20000 or size not in (12,24): raise ValueError("Invalid method list")
            result=[]
            for i in range(count):
                q = p+8+i*size
                if small:
                    va = v+8+i*size
                    a,b,c = struct.unpack_from('<iii',m,q)
                    name = va+a
                    if not direct: name = u64(offset(name))
                    typ, imp = va+4+b, va+8+c
                else: name,typ,imp = struct.unpack_from('<QQQ',m,q)
                result.append({'selector':string(name),'types':string(typ),'imp':hex(imp)})
            return result
        result=[]
        _, size, p = sections['__objc_classlist']
        for i in range(size//8):
            addr=u64(p+8*i)
            try:
                c=offset(addr); ro=offset(u64(c+32)&~7)
                name=string(u64(ro+24))
                if class_filter and not re.search(class_filter,name,re.I): continue
                meta=offset(u64(c)); mr=offset(u64(meta+32)&~7)
                result.append({'class':name,'address':hex(addr),'instance':methods(u64(ro+32)),'class_methods':methods(u64(mr+32))})
            except (ValueError,struct.error): continue
        by_address = {int(c['address'],16): c for c in result}
        if '__objc_catlist' in sections:
            _, size, p = sections['__objc_catlist']
            for i in range(size//8):
                try:
                    cat=offset(u64(p+8*i)); target=by_address.get(u64(cat+8))
                    if target:
                        target['instance'] += methods(u64(cat+16))
                        target['class_methods'] += methods(u64(cat+24))
                except (ValueError,struct.error): continue
        return result

if __name__ == '__main__':
    p=argparse.ArgumentParser();p.add_argument('binary');p.add_argument('--output');p.add_argument('--filter',default='')
    a=p.parse_args();data=dump(a.binary, a.filter)
    if a.filter:
        import re
        data=[c for c in data if re.search(a.filter,c['class'],re.I) or any(re.search(a.filter,m['selector'],re.I) for m in c['instance'])]
    s=json.dumps(data,ensure_ascii=False,indent=2)
    if a.output:
        with open(a.output,'w') as f:f.write(s+'\n')
    else:print(s)
