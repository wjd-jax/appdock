(() => {
  const root = document.querySelector('#developer-setup'); if (!root) return;
  const data = JSON.parse(document.querySelector('#developer-data').textContent);
  const form = document.querySelector('#setup-form');
  const field = name => form.elements.namedItem(name);
  const config = document.querySelector('#config-output'), ci = document.querySelector('#ci-output'), status = document.querySelector('#setup-status');
  const buildEditor = document.querySelector('#build-editor'), buildSummary = document.querySelector('#build-summary'), editBuild = document.querySelector('#edit-build');
  const kitButton = document.querySelector('#download-kit'), configButton = document.querySelector('#download-config'), ciButton = document.querySelector('#download-ci');
  let files = null, provider = 'github', pending = null, timer, version = 0, downloading = false;
  const fileForCI = () => provider === 'github' ? '.github/workflows/team-distribution.yml' : 'ci/team-distribution.gitlab.yml';
  const toast = text => { const box = document.querySelector('#toast'); box.textContent = text; box.style.display='block'; clearTimeout(box.timer); box.timer=setTimeout(()=>box.style.display='none',3000); };
  const enable = () => {
    [kitButton, configButton, ciButton].forEach(button => button.disabled = !files || downloading);
    document.querySelectorAll('[data-setup-copy="config-output"],[data-setup-copy="ci-output"]').forEach(button=>button.disabled=!files);
  };
  const payload = () => { const values=Object.fromEntries(new FormData(form)); values.runner=field('runner').value; return values; };
  const headers = () => ({'Content-Type':'application/json','Accept':'application/json','X-CSRF-Token':document.querySelector('meta[name="csrf-token"]').content});
  const renderCI = () => {
    document.querySelector('#ci-filename').textContent=fileForCI();
    ci.textContent=files?.[fileForCI()] || '配置有效后，在这里生成自动化模板。';
    ci.setAttribute('aria-labelledby','tab-'+provider);
    document.querySelector('#ci-help').textContent=provider==='github' ? '将模板合并到业务仓库默认分支；Runner 需有 self-hosted、company-lan 和所选系统标签。成功链接写入运行摘要。' : '将模板通过 include:local 合并到已有 .gitlab-ci.yml，确保 build 阶段及 Runner 标签匹配。成功 JSON 保存为 Job artifact。';
    ['github','gitlab'].forEach(name=>{const tab=document.querySelector('#tab-'+name);tab.setAttribute('aria-selected',String(name===provider));tab.tabIndex=name===provider?0:-1;});
  };
  const refresh = async () => {
    const current=++version; pending?.abort(); files=null; enable();
    status.className='muted';status.textContent='正在生成配置与自动化模板…';
    const controller=new AbortController();pending=controller;
    try {
      const response=await fetch(root.dataset.previewUrl,{method:'POST',headers:headers(),body:JSON.stringify(payload()),signal:controller.signal});
      if (!response.headers.get('Content-Type')?.includes('application/json')) throw new Error('服务暂时未返回配置，请检查网络后重试。');
      const body=await response.json(); if (!response.ok) throw new Error(body.error || '无法生成配置');
      if(current!==version)return;
      files=body.files;config.textContent=files['.team-distribution.json'];renderCI();status.textContent='';
    } catch(error) {
      if(error.name==='AbortError'||current!==version)return;
      status.className='error';status.textContent=error.message;config.textContent='修正上方配置后重新生成。';renderCI();
    } finally { if(current===version){pending=null;enable();} }
  };
  const schedule = () => {
    ++version; pending?.abort();files=null;enable();clearTimeout(timer);timer=setTimeout(refresh,250);
    const auto=field('trigger').value==='push';field('branch').readOnly=!auto;document.querySelector('#setup-branch-field').hidden=!auto;
    document.querySelector('#trigger-summary').textContent=auto ? `模板将在推送 ${field('branch').value || '指定分支'} 时自动构建，并保留手动入口。提交到业务仓库后才生效。` : '模板仅提供手动触发入口，不会因推送自动构建。';
  };
  const setPreset = () => {
    const value=field('platform').value,preset=data.presets[value];
    field('build').value=JSON.stringify(preset.build);field('artifact').value=preset.artifact;
    buildSummary.textContent=preset.build.join(' ');
    buildEditor.hidden=value!=='custom';editBuild.setAttribute('aria-expanded',String(!buildEditor.hidden));
    if(value==='custom')document.querySelector('#project').open=true;
    field('runner').value=value==='ios'?'macOS':'Linux';field('runner').disabled=value==='ios';
    document.querySelector('#upload-command').textContent=`python3 tools/team_release.py upload /绝对路径/app.${value==='ios'?'ipa':'apk'}`;
    schedule();
  };
  field('platform').addEventListener('change',setPreset);
  editBuild.addEventListener('click',()=>{buildEditor.hidden=!buildEditor.hidden;editBuild.setAttribute('aria-expanded',String(!buildEditor.hidden));if(!buildEditor.hidden)field('build').focus();});
  field('build').addEventListener('input',()=>{try{const command=JSON.parse(field('build').value);buildSummary.textContent=Array.isArray(command)?command.join(' '):'请填写有效的命令数组';}catch{buildSummary.textContent='请填写有效的命令数组';}});
  ['build','artifact','branch'].forEach(name=>field(name).addEventListener('input',schedule));
  ['trigger','runner'].forEach(name=>field(name).addEventListener('change',schedule));
  form.addEventListener('submit',event=>event.preventDefault());
  ['github','gitlab'].forEach(name=>document.querySelector('#tab-'+name).addEventListener('click',()=>{provider=name;renderCI();}));
  document.querySelector('.setup-tabs').addEventListener('keydown',event=>{if(['ArrowLeft','ArrowRight','Home','End'].includes(event.key)){event.preventDefault();provider=event.key==='Home'?'github':event.key==='End'?'gitlab':provider==='github'?'gitlab':'github';renderCI();document.querySelector('#tab-'+provider).focus();}});
  const save = (blob,name) => {const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=name;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),10000);};
  configButton.addEventListener('click',()=>{if(files)save(new Blob([files['.team-distribution.json']],{type:'application/json'}),'.team-distribution.json');});
  ciButton.addEventListener('click',()=>{if(files)save(new Blob([files[fileForCI()]],{type:'text/yaml'}),provider==='github'?'team-distribution.yml':'team-distribution.gitlab.yml');});
  kitButton.addEventListener('click',async()=>{
    if(!files||downloading)return;downloading=true;enable();
    try{const response=await fetch(root.dataset.bundleUrl,{method:'POST',headers:headers(),body:JSON.stringify(payload())});if(!response.ok){const body=await response.json();throw new Error(body.error||'接入包生成失败');}if(!response.headers.get('Content-Type')?.includes('application/zip'))throw new Error('服务返回的接入包格式异常');save(await response.blob(),'team-distribution-kit.zip');toast('接入包已下载，可以把下方指令发给 AI。');}catch(error){toast(error.message);}finally{downloading=false;enable();}
  });
  document.querySelectorAll('[data-setup-copy]').forEach(button=>button.addEventListener('click',async()=>{
    const value=document.getElementById(button.dataset.setupCopy).textContent;
    try{await navigator.clipboard.writeText(value);toast('已复制');}
    catch{
      const input=document.createElement('textarea');input.value=value;input.setAttribute('readonly','');input.style.position='fixed';input.style.left='-9999px';document.body.append(input);input.select();
      let copied=false;try{copied=document.execCommand('copy');}catch{}input.remove();toast(copied?'已复制':'复制失败，请手动选择内容复制');
    }
  }));
  renderCI();setPreset();
})();
