module Constants
using HTTP
using RelocatableFolders

include("types.jl")
using .Types:ResponseTypes

export PACKAGE_DIR, DATA_PATH,
    GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, CONNECT, TRACE, 
    HTTP_METHODS,
    WEBSOCKET, STREAM,
    SPECIAL_METHODS, METHOD_ALIASES, TYPE_ALIASES,
    SWAGGER_VERSION, REDOC_VERSION, CONTENT_TYPES

# Generate a reliable path to our package directory
const PACKAGE_DIR :: String = @path @__DIR__

# Generate a reliable path to our internal data folder that works when the 
# package is used with PackageCompiler.jl
const DATA_PATH :: String = @path joinpath(@__DIR__, "..", "data")

# HTTP Methods
const GET       :: String   = "GET"
const POST      :: String   = "POST"
const PUT       :: String   = "PUT"
const DELETE    :: String   = "DELETE"
const PATCH     :: String   = "PATCH"
const HEAD      :: String   = "HEAD"
const OPTIONS   :: String   = "OPTIONS"
const CONNECT   :: String   = "CONNECT"
const TRACE     :: String   = "TRACE"

const HTTP_METHODS :: Set{String} = Set([GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, CONNECT, TRACE])

# Special Methods
const WEBSOCKET :: String = "WEBSOCKET"
const STREAM    :: String = "STREAM"

const SPECIAL_METHODS :: Set{String} = Set([WEBSOCKET, STREAM])

# Sepcial Method Aliases
const METHOD_ALIASES :: Dict{String,String} = Dict(
    WEBSOCKET   => GET,
    STREAM      => GET
)

const TYPE_ALIASES :: Dict{String, Type} = Dict(
    WEBSOCKET   => HTTP.WebSockets.WebSocket,
    STREAM      => HTTP.Streams.Stream
)

const SWAGGER_VERSION   :: String = "swagger@5.7.2"
const REDOC_VERSION     :: String = "redoc@2.1.2"

# Mapping of ResponseType used in a ResponseWrapper to the MIME type 
const CONTENT_TYPES :: Dict{ResponseTypes.ResponseType, String} = Dict(
    ResponseTypes.Html => "text/html; charset=utf-8",
    ResponseTypes.Text => "text/plain; charset=utf-8",
    ResponseTypes.Json => "application/json; charset=utf-8",
    ResponseTypes.Xml => "application/xml; charset=utf-8",
    ResponseTypes.Js => "application/javascript; charset=utf-8",
    ResponseTypes.Css => "text/css; charset=utf-8",
    ResponseTypes.Binary => "application/octet-stream"
)

end