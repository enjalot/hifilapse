#!/usr/bin/env coffee
fs = require 'fs'
path = require 'path'
knox = require 'knox'
mpu = require 'knox-mpu'
async = require 'async'



setFile = (options, cb) ->
  s3path = options?.path
  filePath = options?.filePath
  bucket = options?.bucket
  useProgress = options?.useProgress
  return cb new Error '400: Must provide an s3 path and a file path' unless path? and filePath?

  auth = getAuth bucket
  client = knox.createClient auth
  stats = fs.statSync filePath
  headers = {
    'Content-Length': stats.size,
    'Content-Type': 'image/jpeg',
    'x-amz-acl': 'public-read'
  }

  console.log 'WARNING: File size is 0' if stats.size is 0

  fileReadStream = fs.createReadStream filePath
  req = client.putStream fileReadStream, s3path, headers, (err, res) ->
    fileReadStream.destroy()
    return cb err, res?.statusCode
  req.on 'error', (err) ->
    return # ignore irrelevant knox tcp errors
  useUploadProgressBar req if useProgress

setFileMultipart = (options, cb) ->
  bucket = options?.bucket
  s3path = options?.path
  useProgress = options?.useProgress
  auth = getAuth bucket
  client = knox.createClient auth

  fileReadStream = fs.createReadStream filePath
  console.log 'setFileMultipart called', filePath

  upload = new mpu
    client: client,
    objectName: s3path
    stream: fileReadStream
    partSize: 734003200
    batchSize: 2
  , (err, data) ->
    fileReadStream.destroy()
    cb(err, data)

  useUploadProgressBar upload if useProgress


handleErrors = (s3res, options, cb) ->
  if /^404$/.test(s3res?.statusCode)
    return cb new Error "404: Document not found #{options?.path}", s3res?.statusCode
  else
    cb()

useDownloadProgressBar = (s3res, cb) ->
  multimeter = require 'multimeter'
  multi = multimeter process
  data = 0
  total = +s3res.headers?['content-length']
  multi.drop (bar) ->
    s3res.on 'data', (chunk) ->
      data += chunk
      # show progress bar
      p = 100 * data.length/total
      if p or p == 0
        bar.percent p
    cb?()

useUploadProgressBar = (req, cb) ->
  multimeter = require 'multimeter'
  multi = multimeter process
  multi.drop (bar) ->
    req.on 'progress', (d) ->
      bar.percent d.percent

getAuth = (bucket) ->
  conf = require './config'
  return {
    key: conf.aws.key
    secret: conf.aws.secret
    bucket: bucket or conf.aws.bucket
  }

#called directly from command line (not required as a module)
if require.main == module
  path = require 'path'
  program = require 'commander'

  program
    .option '-m, --method [upload|process]', 'method can be upload or process, defaults to process', 'process'
    .option '-i, --multipart', 'boolean to specify whether multipart upload should be used'
    .option '-d, --dir <dir>', 'path to directory'
    .option '-b, --bucket <bucket>', 'override the configured s3 bucket'
    .parse process.argv

  filePath = program.file
  conf = require './config'
  bucket = program.bucket or conf.aws.bucket

  dir = program.dir
  basename = path.basename dir
  s3path = "hifilapse/#{basename}"

  method = program.method
  multipart = program.multipart or false
  console.log "Performing #{method} on file #{filePath} for #{program.env} s3 bucket #{bucket}, path #{path}"

  data = []

  # grab all the files in the directory
  fs.readdir dir, (err, files) ->
    if method is 'upload'
      looper = async.each
    else
      looper = async.eachSeries
    looper files, (file, fileCb) ->
      if method is 'upload'
        console.log "uploading file" , file
        upload file, fileCb
      else if method is 'process'
        processFile file, fileCb
    , (err) ->
      console.log "err", err if err
      if method is 'process'
        data.sort (a,b) ->
          a.createdAt - b.createdAt

        data.forEach (d, i) ->
          d.index = i

        console.log "data", data.length
        # save out the file
        str = JSON.stringify(data, null, 2)
        output = path.join(dir, "files.json")
        fs.writeFileSync output, str
        console.log "wrote to", output
        process.exit()
      else if method is 'upload'
        process.exit()

  processFile = (file, cb) ->
    return cb() if file == "files.json"
    filePath = path.join dir, file
    fileS3Path = path.join s3path, file
    re = new RegExp(' ', 'g')
    newFile = {
      name: file,
      url: "https://s3.amazonaws.com/#{bucket}/" + fileS3Path.replace(re, '+')
    }

    fs.stat filePath, (err, stats) ->
      newFile.createdAt = +new Date(stats.mtime)
      newFile.size = stats.size #bytes
      data.push newFile
      cb()

  upload = (file, cb) ->
    filePath = path.join dir, file
    fileS3Path = path.join s3path, file
    console.log "file path", filePath
    console.log "s3 path", fileS3Path 
    if multipart
      setFileMultipart {bucket, path: fileS3Path,filePath,useProgress:false}, (err, result) ->
        #console.log "ERROR:", err if err
        #console.log "Uploaded multipart file #{filePath} to bucket #{bucket}, path #{path}"
        cb err, result
    else
      setFile {bucket,path: fileS3Path,filePath,useProgress:false}, (err, result) ->
        #console.log "ERROR:", err if err
        #console.log "Uploaded file #{filePath} to bucket #{bucket}, path #{path}"
        cb err, result


    
