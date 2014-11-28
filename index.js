// https://github.com/derbyjs/derby-standalone

var app = derby.createApp();
// convenience function for loading templates that are defined as <script type="text/template">
app.registerViews();

// we register our "tabs" component by associating the Tabs class with the 'tabs' template
app.component('player', Player);
function Player() {}
Player.prototype.init = function(model) {
  // init is called at the time of instanciation
};
Player.prototype.create = function(model) {
  var that = this;

  function updateSize() {
    var image = that.model.root.get("_page.images.0");//getImage(0);
    if(!image) return;
    var canvas = that.player;
    that.ctx = canvas.getContext("2d")
    var width;
    if(width = that.model.get("width")) {
      canvas.width = width;
      canvas.height = image.height * (width/image.width);
    } else {
      canvas.width = image.width;
      canvas.height = image.height;
    }
    that.ctx.drawImage(image, 0, 0, canvas.width, canvas.height)
  }

  if(model.get("loaded")) updateSize();
  model.on("change", "loaded", updateSize)

  model.on("change", "current", function() {
    var current = model.get("current");
    var img = model.root.get("_page.images." + current); //getImage(that.model.get("current"))
    if(!img) return;
    try {
      that.ctx.drawImage(img, 0, 0, that.player.width, that.player.height)
    } catch(e) {
      console.log("E!", e, img)
    }
  })

  if(model.get("looping")){
    var time = 0;
    var t0 = 0
    d3.timer(function(elapsed){
      if(model.get("paused")) return false;
      time += elapsed - t0; //milliseconds
      t0 = elapsed;
      var fps = model.get("fps")
      var thresh = 1000/fps
      if(time > thresh) {
        time = 0;
        // a frame's worth of time has passed!
        model.increment("current");
        // if we reach the end, startover
        if(model.get("current") >= model.get("data.length") - 1) {
          model.set("current", 0)
        }
      }
    })
  }
};
Player.prototype.load = function(d) {
  this.model.set("current", d.index)

}
Player.prototype.move = function(evt) {
  if(this.model.get("looping")) return;
  var w = this.player.width;
  var len = this.model.get("data.length")
  var index = Math.floor(evt.offsetX/w * len);
  this.model.set("current", index)
}
Player.prototype.click = function(){
  var paused = this.model.get("paused");
  this.model.set("paused", !paused)
}
function getImage(index) {
  return document.getElementsByClassName("img" + index)[0]
}

app.component('selector', Selector);
function Selector() {}
Selector.prototype.init = function(model) {
  // init is called at the time of instanciation
  var size = model.get("right") - model.get("left")
  model.start("rw", "width", "left", "right", 
    function(width, left, right) {
      return Math.floor(width / (right-left));
    });

  var rw = model.get("rw");
  var size = model.get("right") - model.get("left")
  var range = d3.range(size).map(function(i){
    return {
      x: i * (rw + 1),
      y: 0,
      i: i
    }
  })
  model.set("range", range)
  
  /*
  model.start("range", "data", "left", "right", "ignore", function(data, left, right, ignore){ 
    var size = right - left;
    var range = [];
    data.forEach(function(d,i) {
      var c = range.length;
      if(i > left && i < right) {
        d.x = c * (rw+1);
        d.y = 0;
        
        range.push(d)
      }
    })
    return range;
  })
*/
};
Selector.prototype.hover = function(d) {
  //console.log("d", d);
  var index = this.model.get("left") + d.i;
  var datum = this.model.get("data." +index)
  this.emit("hover", datum)
}
var page = app.createPage();

var url = "http://kijani.s3.amazonaws.com/hifilapse/weatgrass_side/files.json";
d3.json(url, function(err, data){
  //console.log(data);
  data.sort(function(a,b) {
    return a.index - b.index
  })
  var toLoad = data.length;
  data.forEach(function(d,i){ 
    var image = new Image()
    image.src = d.url
    image.onload = function() {
      page.model.set("_page.images." + i, image)
      toLoad--;
      if(toLoad <= 20) {
        page.model.set("_page.loaded", true)
      }
    }
  })
  page.model.set("_page.currentIndex", 1)
  page.model.set("_page.data", data)


  var sizes = [ 64, 128, 256, 512]
  var selectors = []
  sizes.forEach(function(s,i) {
    selectors.push({
      n: s,
      h: 50,
      l: 0,
      r: s
    })
  })
  page.model.set("_page.selectors", selectors)
  page.model.set("_page.fps", 24)

  window.MODEL = page.model;
 
  document.body.appendChild(page.getFragment('body'));
})




function draw(img, ctx, scale) {
  if(!scale) scale = 1;
  var imgData = ctx.getImageData(0, 0, img.width, img.height);
  ctx.putImageData(imgData, 0, 0)
}