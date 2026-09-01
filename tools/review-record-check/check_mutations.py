import argparse,copy,hashlib,json,subprocess,sys
from pathlib import Path
root=Path('/tmp/review-record-validator-refutation')
parser=argparse.ArgumentParser()
parser.add_argument('runner',type=Path,nargs='?',default=Path('/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/tools/review-record-check/run.py'))
runner=parser.parse_args().runner.resolve()
source=runner.read_bytes()
digest=hashlib.sha256(source).hexdigest()
run_dir=root/digest[:16]
run_dir.mkdir(exist_ok=True)
(run_dir/'reviewed-run.py').write_bytes(source)
base={
 'recovery-manifest.json':{'areas':[{'area':'probe','findings':1}],'initialEntries':1,'expectedSessions':['S1']},
 'initial/probe.json':{'findings':[{'title':'Original finding'}]},
 'findings.json':{'findings':[{'id':'probe-01','originalTitle':'Original finding','status':'unresolved','evidence':'Source path:12 observed; runtime pending.','verificationMethod':'Source inspection','remainingVerification':'Run controlled experiment.'}]},
 'session-audit.json':{'sessions':[{'session':'S1','claims':[{'claim':'No app source changed.','status':'confirmed','evidence':'git diff source path is empty.'}]}]}}
cases={}
cases['baseline']=copy.deepcopy(base)
x=copy.deepcopy(base);x['findings.json']['findings']=[];cases['omit_finding']=x
x=copy.deepcopy(base);x['findings.json']['findings']*=2;cases['duplicate_finding']=x
x=copy.deepcopy(base);x['session-audit.json']['sessions']=[];cases['omit_session']=x
x=copy.deepcopy(base);x['findings.json']['findings'][0]['status']='all clear';cases['invented_disposition']=x
x=copy.deepcopy(base);x['findings.json']['findings'][0]['evidence']='   ';cases['whitespace_evidence']=x
x=copy.deepcopy(base);x['findings.json']['findings'][0]['evidence']=True;cases['boolean_evidence']=x
x=copy.deepcopy(base);x['findings.json']['findings'][0]['verificationMethod']={'no':'proof'};cases['object_method']=x
x=copy.deepcopy(base);x['session-audit.json']['sessions'][0]['claims'][0]['status']='usage_limit_no_review';cases['failed_claim_status']=x
x=copy.deepcopy(base);x['recovery-manifest.json']['expectedSessions']*=2;cases['duplicate_session_roster']=x
x=copy.deepcopy(base);x['recovery-manifest.json']['areas']*=2;cases['duplicate_area_roster']=x
x=copy.deepcopy(base);x['recovery-manifest.json']['expectedSessions']=[];x['session-audit.json']['sessions']=[];cases['removed_session_roster']=x
x=copy.deepcopy(base);x['recovery-manifest.json']={'areas':[],'initialEntries':0,'expectedSessions':[]};x['findings.json']['findings']=[];x['session-audit.json']['sessions']=[];cases['empty_roster']=x
results=[]
for name,files in cases.items():
 d=root/name;d.mkdir(exist_ok=True)
 for path,data in files.items():
  p=d/path;p.parent.mkdir(exist_ok=True);p.write_text(json.dumps(data))
 p=subprocess.run([sys.executable,str(runner),str(d)],capture_output=True,text=True)
 result=dict(case=name,exit=p.returncode,stdout=p.stdout,stderr=p.stderr)
 results.append(result)
 print(name,p.returncode,(p.stdout or p.stderr).splitlines()[0])
(run_dir/'results.json').write_text(json.dumps(results,indent=2)+'\n')
unexpected=[r for r in results if r['exit'] != (0 if r['case']=='baseline' else 1)]
summary={'checker_sha256':digest,'cases':len(results),'baseline_passed':results[0]['exit']==0,'negative_cases_rejected':sum(r['exit']==1 for r in results[1:]),'unexpected':unexpected}
(run_dir/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary))
sys.exit(bool(unexpected))
