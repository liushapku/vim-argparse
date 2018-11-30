
let s:x = '--lines-a,1,2,3 -*lines([1,2,3] -*lines[1+3,2,3 -a1,2,3 6+7 3+4 _.a -*%a4%5?? _.a -b% % %?< %?<? --c>a'
echo scripting#parser#parse(s:x, {'a': 3, 'type':{'b': '<', 'a':'[', '':'('}})

let s:x = '--lines{1:1+3,2:2,3:3 -*lines}a:b,2:4 -*lines]c:{i->i*2}'
echo scripting#parser#parse(s:x, {'a': 3, 'type':{'b': '<', 'a':'[', '':'('}})
