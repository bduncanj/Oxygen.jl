module Constants

export HOST, PORT, localhost, MIME_MAP

const HOST = "127.0.0.1"
const PORT = 6060 # 8080 port is frequently used
const localhost = "http://$HOST:$PORT"

const MIME_MAP::Dict{Symbol,String} = Dict(
    :Html => "text/html",
    :Text => "text/plain",
    :Json => "application/json",
    :Xml => "application/xml",
    :Js => "application/javascript",
    :Css => "text/css",
    :Binary => "application/octet-stream"
)

end