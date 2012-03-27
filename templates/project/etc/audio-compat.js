function audioCompat() {
    var audioTag = window.document.createElement('audio');
    //Check for HTML5 audio tag compatibility
    if (!(audioTag.canPlayType && audioTag.canPlayType('audio/mpeg') && (audioTag.canPlayType('audio/mpeg') != 'no'))){
	//not compatible - fallback to Flash
	AudioPlayer.setup("etc/player/player.swf", { width: 290 });  
	var audioTags = window.document.getElementsByTagName('audio');
	var audioTagMeta = [];
	for (var i = 0; i < audioTags.length; i++) {
	    var tag = audioTags[i];
	    if (! tag.id){
		tag.id = '_typingpool_audio_' + i;
	    }
	    audioTagMeta.push({'id':tag.id, 'src':tag.src});
	}
	for (var i = 0; i < audioTagMeta.length; i++) {
	    var tagMeta = audioTagMeta[i];
	    AudioPlayer.embed(tagMeta.id, {'soundFile': tagMeta.src, 'noinfo': 'yes'});
	}
    }
}

if (window.addEventListener){ window.addEventListener('load', audioCompat, false) }
else if (document.addEventListener){ document.addEventListener('load', audioCompat, false) }
else if (window.attachEvent){ window.attachEvent('onload', audioCompat) }
