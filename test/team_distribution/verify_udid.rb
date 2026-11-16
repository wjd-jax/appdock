require 'action_dispatch/testing/integration'
raise 'Isolation required' unless ActiveRecord::Base.connection_db_config.database == 'appdock_verify'
def check(label)
 raise label unless yield
 puts "PASS #{label}"
end
s=ActionDispatch::Integration::Session.new(Rails.application)
s.host!("apps.example.com:#{ENV.fetch('APPDOCK_ACCEPTANCE_HTTPS_PORT', '18443')}");s.https!
count=Device.count
s.get('/udid');check('UDID page'){s.response.status==200 && s.response.body.include?('AppDock')}
s.get('/udid/profile');check('profile MIME'){s.response.media_type=='application/x-apple-aspen-config'}
p=Plist.parse_xml(s.response.body);c=p['PayloadContent']['Challenge'];url=p['PayloadContent']['URL']
check('minimum attributes'){p['PayloadContent']['DeviceAttributes']==%w[UDID PRODUCT VERSION]}
check('same host callback'){URI(url).host=='apps.example.com' && URI(url).scheme=='https'}
key=OpenSSL::PKey::RSA.new(2048);cert=OpenSSL::X509::Certificate.new;cert.version=2;cert.serial=1;cert.subject=cert.issuer=OpenSSL::X509::Name.parse('/CN=Isolated Test');cert.public_key=key.public_key;cert.not_before=Time.now-60;cert.not_after=Time.now+3600;cert.sign(key,OpenSSL::Digest.new('SHA256'))
pack=->(attrs){OpenSSL::PKCS7.sign(cert,key,Plist::Emit.dump(attrs),[],OpenSSL::PKCS7::BINARY).to_der}
attrs={'CHALLENGE'=>c,'UDID'=>'00008110-0011223344556677','PRODUCT'=>'<script>alert(1)</script>','VERSION'=>'18.0'}
post=->(body){s.post(URI(url).request_uri,params:body,headers:{'CONTENT_TYPE'=>'application/pkcs7-signature'})}
post.call(pack.call(attrs.merge('CHALLENGE'=>'bad')));check('wrong challenge'){s.response.status==422}
post.call('invalid');check('invalid CMS'){s.response.status==422}
post.call('a'*131073);check('size bound'){s.response.status==422}
post.call(pack.call(attrs));check('callback without browser CSRF'){s.response.status==301}
result=URI(s.response.location).request_uri
check('identifier absent from URL'){!result.include?(attrs['UDID'])}
s.get(result);check('result escaped'){s.response.status==200 && s.response.body.include?('&lt;script&gt;') && !s.response.body.include?('<script>alert')}
check('result private'){s.response.headers['Cache-Control'].include?('no-store') && s.response.body.include?('content="no-referrer"')}
post.call(pack.call(attrs));check('one use challenge'){s.response.status==422}
Rails.cache.delete("appdock:udid:result:#{result.split('/').last}")
s.get(result);check('expired result'){s.response.status==410}
check('no device registered'){Device.count==count}
s.patch('/workspace/apps/12',params:{app:{name:'Must not save'}});check('ordinary CSRF preserved'){s.response.status==422}
puts 'All UDID isolated checks passed'
