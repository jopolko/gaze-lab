class_name RScale
## Render scale: how many pixels the game draws, as a fraction of the screen's.
##
## In the browser this must NOT be Viewport.scaling_3d_scale. With that below 1 the browser renderer copies the depth buffer from the small picture to the
## full-size one every frame, and a scaled depth copy has no fast path on Windows graphics drivers (measured on an Intel UHD 620: 25 to 40 ms a frame,
## 57 fps with the copy skipped against 21 with it). So in the browser the whole canvas is made smaller instead and the browser stretches it to the
## window, which costs nothing: the page's devicePixelRatio is what the engine sizes its canvas from, and it re-reads it every frame.

static var cur: float = 1.0

const JS := "(function(s){try{if(!window.__rsInit){var o=window,d=null;while(o&&!d){d=Object.getOwnPropertyDescriptor(o,'devicePixelRatio');o=Object.getPrototypeOf(o);}var v=window.devicePixelRatio||1;var real=(d&&d.get)?function(){return d.get.call(window)||1;}:function(){return v;};window.__rsReal=real;window.__rsScale=1;Object.defineProperty(window,'devicePixelRatio',{configurable:true,get:function(){return real()*window.__rsScale;}});window.__rsInit=1;}window.__rsScale=s;return 1;}catch(e){return 0;}})(%s)"


static func set_scale(vp: Viewport, s: float) -> void:
	s = clampf(s, 0.4, 1.0)
	if OS.has_feature("web"):
		if vp != null and vp.scaling_3d_scale != 1.0:
			vp.scaling_3d_scale = 1.0
		if absf(s - cur) < 0.005:
			return
		cur = s
		JavaScriptBridge.eval(JS % String.num(s, 3))
	else:
		cur = s
		if vp != null:
			vp.scaling_3d_scale = s


## The canvas's pixel count at full scale.
static func full_px() -> float:
	var sz := DisplayServer.window_get_size()
	return maxf(float(sz.x) * float(sz.y) / (cur * cur), 1.0)
