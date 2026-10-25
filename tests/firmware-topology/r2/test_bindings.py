"""Actual bindings.h macros and actual new method table: no mocked BIND macro."""
import ast, pathlib, subprocess, tempfile, hashlib
D=pathlib.Path(__file__).resolve().parent
tree=ast.parse((D.parent/'test_composed.py').read_text())
prefix=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='prefix' for t in n.targets))
prefix=prefix.replace('#define BIND_NODE_METHODS(n,m) bind_methods(n,#m)','')
prefix=prefix.replace('#define NODE_METHODS(n) struct method n[]','')
header=(D/'bindings.h').read_text()
macros=header[header.index('#define BIND_NODE_METHODS'):header.index('#define REGISTER_NODE( name )')]
binding=r"""
typedef struct { const char *name; void *func; } method_t;
static int called;
static void bind_node_methods(int node,int flags,int size,const method_t *methods,int count){
 assert(node==7);assert(flags==0);assert(size==sizeof(int));assert(count==9);
 assert(!strcmp(methods[2].name,"decode-unit"));assert(methods[2].func);
 assert(!strcmp(methods[3].name,"encode-unit"));assert(methods[3].func);
 called++;
}
"""
with tempfile.TemporaryDirectory(prefix='actual-node-binding-') as td:
 for label,path in [('r1',D.parent/'ide.c'),('r2',D/'ide.c')]:
  src=path.read_text()
  start=src.index('#ifdef CONFIG_SPARC64\n/* Same two-cell')
  helper=src[start:src.index('static void set_cd_alias',start)]
  unit=pathlib.Path(td)/(label+'.c');exe=unit.with_suffix('')
  unit.write_text(prefix+binding+macros+helper+'\nint main(void){ BIND_NODE_METHODS(7,ob_ide_sun4u_ctrl);assert(called==1);return 0;}\n')
  p=subprocess.run(['cc','-std=c99','-DCONFIG_SPARC64','-fsanitize=address,undefined',str(unit),'-o',str(exe)],capture_output=True,text=True)
  if label=='r1':
   assert p.returncode!=0 and 'ob_ide_sun4u_ctrl_flags_' in p.stderr and 'ob_ide_sun4u_ctrl_size_' in p.stderr,p.stderr
   print('R1 expected compile FAIL: actual metadata flags_/size_ absent')
   (D/'r1-binding-failure.log').write_text(p.stderr)
  else:
   assert p.returncode==0,p.stderr
   subprocess.run([str(exe)],check=True)
   print('R2 actual bindings macros/table/runtime metadata PASS: flags0,size sizeof(int),9methods,decode+encode')
print('bindings.h SHA256',hashlib.sha256((D/'bindings.h').read_bytes()).hexdigest())
