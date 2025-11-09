class JavaScriptInjector {
  static String getScalingScript(double deviceWidth) {
    return """
      (function(){
        function applyScale(){
          try{
            var body=document.body,doc=document.documentElement;
            var w=doc.scrollWidth||body.scrollWidth||window.innerWidth||$deviceWidth;
            var s=$deviceWidth/w;if(s>1)s=1.0;
            body.style.transform='scale('+s+')';
            body.style.transformOrigin='top left';
            body.style.width=(100/s)+'%';
            body.style.margin='0';body.style.padding='0';body.style.overflowX='hidden';
          }catch(e){}
        }
        if(document.readyState==='complete'||document.readyState==='interactive')applyScale();
        else document.addEventListener('DOMContentLoaded',applyScale,{once:true});
        setTimeout(applyScale,200);
      })();
    """;
  }

  static String getCssZoomScript(double deviceWidth) {
    return '''
      (function(){
        try{
          var b=document.body,d=document.documentElement;
          var cw=d.scrollWidth||(b&&b.scrollWidth)||window.innerWidth;
          if(!cw||cw<=0)return;
          var s=$deviceWidth/cw;if(s>1)s=1.0;
          b.style.transform='scale('+s+')';
          b.style.transformOrigin='top left';
          b.style.width=(100/s)+'%';
          b.style.margin='0';b.style.padding='0';b.style.overflowX='hidden';
        }catch(e){}
      })();
    ''';
  }

  static String getCredentialCaptureScript() {
    return '''(
      (function(){
        try{
          var u=document.querySelector('input[name="username"], input#ft_un, input[name="user"], input[name="uid"], input[type="text"]');
          var p=document.querySelector('input[name="password"], input#ft_pd, input[type="password"]');
          
          if(u && p && !window._credCaptureSet) {
            window._credCaptureSet = true;
            window._capturedCreds = {username: null, password: null};
            
            function capture() {
              if(u.value) window._capturedCreds.username = u.value;
              if(p.value) window._capturedCreds.password = p.value;
              console.log('Captured:', window._capturedCreds);
            }
            
            u.addEventListener('input', capture);
            p.addEventListener('input', capture);
            u.addEventListener('change', capture);
            p.addEventListener('change', capture);
            
            var form = u.closest('form');
            if(form) {
              form.addEventListener('submit', function() {
                capture();
                console.log('Form submitted with:', window._capturedCreds);
              });
            }
          }
          
          return JSON.stringify({
            username: window._capturedCreds?.username || (u ? u.value : null),
            password: window._capturedCreds?.password || (p ? p.value : null)
          });
        }catch(e){
          console.error('Capture error:', e);
          return "{}";
        }
      })();
    )''';
  }

  static String getOverLimitCheckScript() {
    return '''(
      (function(){
        try{
          var t=(document.body&&document.body.innerText||'').toLowerCase();
          return t.includes("concurrent authentication over limit")||
                 t.includes("already logged")||
                 t.includes("over limit")||
                 t.includes("you are already logged in");
        }catch(e){return false;}
      })()
    )''';
  }

  static String getLoginFormExistsScript() {
    return '''(
      (function(){
        try{
          var sel=document.querySelector('input[name="username"],input#ft_un,input[name="user"],input[name="uid"],input[type="text"]');
          return sel!=null;
        }catch(e){return false;}
      })()
    )''';
  }

  static String getAutoFillScript(String username, String password) {
    final escapedUser = _escapeForJsString(username);
    final escapedPass = _escapeForJsString(password);
    
    return '''
      (function(){
        try{
          var u=document.querySelector('input[name="username"],input#ft_un,input[name="user"],input[name="uid"],input[type="text"]');
          var p=document.querySelector('input[name="password"],input#ft_pd,input[type="password"]');
          if(u)u.value=$escapedUser;
          if(p)p.value=$escapedPass;
          
          window._capturedCreds = {username: $escapedUser, password: $escapedPass};
          console.log('Stored credentials in window._capturedCreds');
          
          var b=document.querySelector('input[type="submit"],button[type="submit"],button[name="login"],#login,.loginbtn,.btn-primary,button');
          if(b){b.click();return"clicked";}
          var f=document.querySelector('form');
          if(f){f.submit();return"submitted";}
          return"no-submit";
        }catch(e){return"error:"+e;}
      })();
    ''';
  }

  static String getStoredCredentialsScript() {
    return '''(
      (function(){
        try{
          if(window._capturedCreds) {
            console.log('Retrieved from window:', window._capturedCreds);
            return JSON.stringify(window._capturedCreds);
          }
          return "{}";
        }catch(e){
          console.error('Retrieve error:', e);
          return "{}";
        }
      })()
    )''';
  }

  static String _escapeForJsString(String raw) {
    final e = raw
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r');
    return "'$e'";
  }
}