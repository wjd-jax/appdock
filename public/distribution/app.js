(() => {
  const csrf = () => document.querySelector('meta[name="csrf-token"]')?.content || '';
  const toast = (message) => { const el=document.querySelector('#toast'); el.textContent=message; el.style.display='block'; clearTimeout(el.timer); el.timer=setTimeout(()=>el.style.display='none',2800); };
  document.addEventListener('click', async event => {
    const copy=event.target.closest('[data-copy],[data-copy-target]');
    if(copy){event.preventDefault();const value=copy.dataset.copy || document.getElementById(copy.dataset.copyTarget)?.value;try{await navigator.clipboard.writeText(value);toast(copy.dataset.copySuccess||'链接已复制');}catch{toast('复制失败，请选中链接手动复制');}}
    const confirmed=event.target.closest('[data-confirm]');
    if(confirmed && !window.confirm(confirmed.dataset.confirm))event.preventDefault();
  });
  const ua=navigator.userAgent; const platform=/iPhone|iPad|iPod/.test(ua)||(/Macintosh/.test(ua)&&navigator.maxTouchPoints>1)?'iOS':/Android/.test(ua)?'Android':null;
  document.querySelectorAll('.udid-page').forEach(el=>el.dataset.device=platform==='iOS'?'ios':'other');
  document.querySelectorAll('[data-platform-card]').forEach(card=>card.classList.toggle('preferred',card.dataset.platformCard===platform));
  document.querySelectorAll('[data-device-hint]').forEach(el=>{if(platform && platform!==el.dataset.deviceHint)el.textContent=`当前设备是 ${platform}，这个安装包适用于 ${el.dataset.deviceHint}。请确认选择正确平台。`;if(/MicroMessenger|DingTalk/.test(ua))el.textContent='请通过右上角菜单，在系统浏览器中打开此页后安装。';});
  document.querySelector('#app-search')?.addEventListener('input',event=>{const query=event.target.value.toLowerCase().trim();document.querySelectorAll('[data-app-name]').forEach(card=>card.hidden=!card.dataset.appName.includes(query));});
  const form=document.querySelector('#upload-form'); if(!form)return;
  const fileInput=form.querySelector('#package-file'), preview=form.querySelector('#package-preview'), message=form.querySelector('#upload-message'), submit=form.querySelector('#upload-submit'), retry=form.querySelector('#upload-retry'), progress=form.querySelector('#upload-progress'), result=form.querySelector('#upload-result'), drop=form.querySelector('#dropzone'), duplicateOptions=form.querySelector('#duplicate-options'), duplicateCheck=form.querySelector('[name="allow_duplicate"]');
  const dialog=form.querySelector('#upload-dialog'), close=form.querySelector('#upload-close');
  close.addEventListener('click',()=>dialog.close());
  dialog.addEventListener('cancel',event=>{if(busy)event.preventDefault();});
  let inspected=false, inspecting=null, busy=false, metadata=null;
  const status=(text,error=false)=>{message.textContent=text;message.classList.toggle('upload-error',error);};
  const submitLabel=()=>{submit.textContent=metadata?.duplicate&&!duplicateCheck.checked?'使用已有安装包 ↗':'开始上传 ↑';};
  const inspect=async()=>{
    inspecting?.abort();inspected=false;metadata=null;preview.hidden=true;result.hidden=true;duplicateOptions.hidden=true;duplicateCheck.checked=false;retry.hidden=true;progress.hidden=true;progress.value=0;submit.disabled=true;submitLabel();
    const file=fileInput.files[0];
    if(!file){status('选择文件后，将自动检查包信息。');return;}
    if(!dialog.open)dialog.showModal();
    form.querySelector('#file-label').textContent=file.name;
    form.querySelector('#file-hint').textContent='点击可更换安装包';
    if(!/\.(ipa|apk)$/i.test(file.name)){status('请选择 IPA 或 APK 安装包。',true);return;}
    status('正在识别应用并检查重复文件…');
    const data=new FormData();data.set('file',file);
    const controller=new AbortController();inspecting=controller;
    try{
      const response=await fetch(form.dataset.inspectUrl,{method:'POST',headers:{'X-CSRF-Token':csrf(),'Accept':'application/json'},body:data,signal:controller.signal});
      if(!response.headers.get('Content-Type')?.includes('application/json'))throw new Error('服务暂时不可用，请点击重新识别重试。');
      const body=await response.json();if(!response.ok)throw new Error(body.error||'无法识别安装包');
      if(inspecting!==controller)return;
      metadata=body;inspected=true;preview.hidden=false;preview.replaceChildren();
      const title=document.createElement('strong');title.textContent=`${body.name||'应用'} · ${String(body.platform).toLowerCase()==='ios'?'iOS':'Android'} · ${body.version||'版本待识别'}`;
      preview.append(title,document.createElement('br'),document.createTextNode(`${body.bundle_id||''} · ${(body.size/1024/1024).toFixed(2)} MB`));
      if(body.duplicate){const warning=document.createElement('p');warning.textContent='已有相同安装包，可直接使用原版本链接。';preview.append(warning);duplicateOptions.hidden=false;}
      status(body.duplicate?'已找到相同安装包，可直接生成已有版本的下载链接。':'包信息已就绪，可直接上传或补充更新说明。');submitLabel();
    }catch(error){if(error.name!=='AbortError'&&inspecting===controller){status(error instanceof TypeError?'识别连接失败，请检查网络后重新识别。':error.message,true);retry.textContent='重新识别';retry.hidden=false;}}
    finally{if(inspecting===controller){inspecting=null;submit.disabled=!inspected;}}
  };
  document.querySelector('[data-select-package]')?.addEventListener('click',event=>{event.preventDefault();fileInput.click();});
  fileInput.addEventListener('change',inspect);duplicateCheck.addEventListener('change',submitLabel);
  ['dragenter','dragover'].forEach(name=>drop.addEventListener(name,event=>{event.preventDefault();if(!busy)drop.classList.add('dragging');}));
  ['dragleave','drop'].forEach(name=>drop.addEventListener(name,()=>drop.classList.remove('dragging')));
  drop.addEventListener('drop',event=>{event.preventDefault();if(busy)return;const file=event.dataTransfer.files[0];if(file){const transfer=new DataTransfer();transfer.items.add(file);fileInput.files=transfer.files;inspect();}});
  const safeURL=value=>{const url=new URL(value,location.origin);if(url.origin!==location.origin||!['http:','https:'].includes(url.protocol))throw new Error('返回的下载链接异常，请联系维护同事。');return url.href;};
  const renderResult=body=>{
    const url=safeURL(body.release_url),appURL=safeURL(body.app_url||body.workspace_url),qr=safeURL(body.qrcode_url);
    result.replaceChildren();result.className='upload-success-grid';
    const content=document.createElement('div'),badge=document.createElement('span'),title=document.createElement('h2'),description=document.createElement('p'),actions=document.createElement('div'),link=document.createElement('a'),copy=document.createElement('button'),appLink=document.createElement('a'),qrImage=document.createElement('img');
    badge.className='badge green';badge.textContent=body.duplicate?'已有版本已就绪':'上传成功';title.textContent=metadata?.name?`${metadata.name} 已可下载安装`:'安装包已可下载安装';description.textContent='把下载链接或二维码分享给团队即可。';
    actions.className='row';link.className='button';link.href=url;link.target='_blank';link.rel='noopener';link.textContent='打开下载页 ↗';
    copy.type='button';copy.className='button secondary';copy.dataset.copy=url;copy.textContent='复制下载链接';actions.append(link,copy);
    appLink.className='text-link';appLink.href=appURL;appLink.textContent='查看应用与历史版本 →';
    const qrURL=new URL(qr);qrURL.searchParams.set('size','large');qrImage.className='result-qr';qrImage.src=qrURL.href;qrImage.alt='当前版本下载二维码';content.append(badge,title,description,actions,appLink);result.append(content,qrImage);result.hidden=false;
  };
  const upload=event=>{
    event?.preventDefault();if(busy)return;
    if(!inspected){status('请先选择并完成安装包识别。',true);return;}
    const data=new FormData(form);busy=true;close.disabled=true;fileInput.disabled=true;duplicateCheck.disabled=true;form.querySelector('#upload-changelog').disabled=true;submit.disabled=true;submit.textContent='正在上传…';retry.hidden=true;progress.hidden=false;progress.value=0;result.hidden=true;
    const xhr=new XMLHttpRequest();xhr.open('POST',form.dataset.uploadUrl);xhr.setRequestHeader('X-CSRF-Token',csrf());xhr.setRequestHeader('Accept','application/json');xhr.timeout=30*60*1000;
    const finish=()=>{busy=false;close.disabled=false;fileInput.disabled=false;duplicateCheck.disabled=false;form.querySelector('#upload-changelog').disabled=false;submit.disabled=false;submitLabel();};
    const failure=text=>{finish();status(text,true);retry.textContent='重试上传';retry.hidden=false;};
    xhr.upload.onprogress=event=>{if(event.lengthComputable){progress.value=event.loaded/event.total*100;status(event.loaded===event.total?'文件上传完成，正在保存…':`上传中 ${Math.round(progress.value)}%`);}};
    xhr.onload=()=>{
      let body;try{body=JSON.parse(xhr.responseText);}catch{return failure('服务暂时未返回结果，请稍后重试。');}
      if(xhr.status<200||xhr.status>=300)return failure(body.error||'上传失败，请重试。');
      try{renderResult(body);}catch(error){return failure(error.message);}
      finish();progress.value=100;status(body.duplicate?'已使用已有版本，没有重复保存文件。':'上传完成，团队现在可以下载安装。');result.scrollIntoView({behavior:'smooth',block:'nearest'});
    };
    xhr.onerror=()=>failure('网络连接失败，文件仍保留，可直接重试。');xhr.ontimeout=()=>failure('上传超时，请检查网络后重试。');status('准备上传…');xhr.send(data);
  };
  form.addEventListener('submit',upload);retry.addEventListener('click',event=>inspected?upload(event):inspect());
})();
