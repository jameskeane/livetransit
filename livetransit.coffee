require('zappa') (zappa) ->
    @enable 'default layout'
    @use static: __dirname + '/public'
    
    http = require 'http'
    xmlstream = require 'xml-stream'
    delay = (func) -> setTimeout func, 5000

    queryVehicles = (agency, lastEpochUpdate) ->
        http.get
            host: 'webservices.nextbus.com'
            path: "/service/publicXMLFeed?command=vehicleLocations&a=#{agency}&t=#{lastEpochUpdate}"
        , (res) ->
            res.setEncoding 'utf8'
            xml = new xmlstream res
            xml.on 'updateElement: vehicle', (vehicle) ->
                zappa.io.sockets.emit 'update',  vehicle['$']

            xml.on 'updateElement: lastTime', (lastTime) ->
                console.log "Updated #{agency} vehicle information at: #{lastTime['$'].time}"
                delay -> queryVehicles agency, lastTime['$'].time

    startService = ->
        http.get
            host: 'webservices.nextbus.com'
            path: "/service/publicXMLFeed?command=agencyList"
        , (res) -> 
            res.setEncoding 'utf8'

            xml = new xmlstream(res)
            xml.on 'updateElement: agency', (agency) ->
                queryVehicles agency['$'].tag, 0

    startService()

    # Handle the root entry point
    @get '/': -> @render 'index'

    # Client side application logic
    @client '/app.js': ->
        @connect()

        # Initialize the map, and give it the cloudmade tiles
        map = new L.Map 'map'
        cmURL = 'http://{s}.tile.cloudmade.com/bc9a493b41014caabb98f0471d759707/997/256/{z}/{x}/{y}.png'
        cm = new L.TileLayer(
            'http://{s}.tile.cloudmade.com/bc9a493b41014caabb98f0471d759707/997/256/{z}/{x}/{y}.png',
            {maxZoom: 18, attribution: ''}
        )
        
        # Set the base location to Toronto :)
        toronto = new L.LatLng(43.725956, -79.364548) # geographical point (longitude and latitude)
        map.setView(toronto, 12).addLayer cm
        
        # See if the user wants to share their location, and use it
        if navigator.geolocation
            navigator.geolocation.getCurrentPosition (position) ->
                location = new L.LatLng(position.coords.latitude, position.coords.longitude)
                map.setView(location, 12)

        vehiclePositions = {}
        #map.on 'viewreset', () ->
        #    for id, vehicle of vehiclePositions
        #        vehicle.setZoom map.getZoom()
        
        @on update: (o) ->
            console.log 'update: ', o
            vehicle = o.data
            markerLocation = new L.LatLng(parseFloat(vehicle.lat), parseFloat(vehicle.lon))

            if vehicle.id of vehiclePositions
                vehiclePositions[vehicle.id].setLatLng markerLocation
                vehiclePositions[vehicle.id].setHeading parseFloat vehicle.heading
            else
                vehiclePositions[vehicle.id] = new L.Vehicle(
                    markerLocation, parseFloat(vehicle.heading), 12) #map.getZoom())
                map.addLayer vehiclePositions[vehicle.id]
        
    # Client side vehicle marker
    @client '/vehicle.map.js': ->
        generateMarker = (heading, zoom) ->
            el = document.createElement 'canvas'
            el.width = 26
            el.height = 26

            ctx = el.getContext '2d'
            ctx.save()
            ctx.translate( 13, 13 )
            ctx.rotate( heading * Math.PI / 180 )
            ctx.translate( -13, -13 )
            if zoom < 12
                ctx.scale zoom/24, zoom/24
            ctx.drawImage( document.getElementById('vehicle-marker'), 0, 0 )
            ctx.restore()

            return L.Icon.extend
                iconUrl: el.toDataURL()
                shadowUrl: ''
                shadowSize: new L.Point(0,0)
                iconSize: new L.Point(26, 26)
                iconAnchor: new L.Point(1, 1)
                popupAnchor: new L.Point(1, 1)

        L.Vehicle = L.Marker.extend
            initialize: (latlng, heading, zoom, options) ->
                if not options? then options = {}
                options['icon'] = new (generateMarker(heading, zoom))()
                L.Util.setOptions(this, options)
                @_latlng = latlng
                @_heading = heading
                @_zoom = zoom
            setZoom: (zoom) ->
                @_zoom = zoom
                @setIcon new (generateMarker(@_heading, @_zoom))()
            getHeading: () -> this._heading
            setHeading: (heading) ->
                if @_heading isnt heading
                    @_heading = heading
                    @setIcon(new (generateMarker(heading))())

    @view index: ->
        doctype 5
        html style: 'width:100%; height:100%; margin:0;padding:0;', ->
            head ->
                meta charset: 'utf-8'
                title 'Transit Live Maps'
                meta name:'description', content:''
                meta name: 'author', content:'http://jameskeane.ca'
    
                link rel:'stylesheet', href:'/leaflet.css'
                ie 'lte IE8', ->
                    link rel:'stylesheet', href:'/leaflet.ie.css'
      
                script src:'/socket.io/socket.io.js'
                script src: '/zappa/zappa.js'
    
            body style:'width:100%; height:100%; margin:0;padding:0;', ->
                img id:'vehicle-marker', src:'/images/vehicle-marker.png', style:'display:none;'
                div id:'map', style:'height: 100%'
    
                script src:'/leaflet.js'
                script src:'/vehicle.map.js'
                script src:'/app.js'

