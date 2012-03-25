    function setAmazonAssignmentId(){
      var params = window.location.search.substring(1).split('&');
      for (var i = 0; i < params.length; i++){
        var param = params[i].split('=');
        var key = param[0];
        var value = param[1];
        if (key == 'assignmentId'){
          if (value == 'ASSIGNMENT_ID_NOT_AVAILABLE'){
            var input = document.getElementById('disable_on_preview');
            if (input){
              input.setAttribute('disabled', 'disabled');
              var span = document.createElement('span');
              span.setAttribute('class', 'disabled_message');
              span.appendChild(document.createTextNode('Disabled because you are previewing this HIT.')); 
              inputSibling = input.nextSibling;
              if (inputSibling){
                input.parentNode.insertBefore(span, inputSibling);
              }
              else{
                input.parentNode.appendChild(span);
              }
            } 
          }
          else{
            document.getElementById('assignmentId').value = value
          }
        }
        else if (key == 'turkSubmitTo'){
          form = document.getElementById('turkForm');
          if (form){
            form.setAttribute('action', decodeURIComponent(value) + '/mturk/externalSubmit');
          }
        }
      }
    }
