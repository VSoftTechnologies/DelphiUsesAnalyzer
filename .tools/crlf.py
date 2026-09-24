"""Normalise the given files to CRLF, in place. Windows repo convention."""
import io, sys
for path in sys.argv[1:]:
    text = io.open(path, encoding='utf-8', newline='').read()
    text = text.replace('\r\n', '\n').replace('\r', '\n').replace('\n', '\r\n')
    io.open(path, 'w', encoding='utf-8', newline='').write(text)
    print('crlf: %s' % path)
