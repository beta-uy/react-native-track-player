//
//  Transcript.swift
//  Podcastar
//
//  Created by Carolina Aitcin on 3/20/19.
//  Copyright © 2019 Facebook. All rights reserved.
//

import Foundation
import Speech
import AVFoundation
import AudioToolbox
import AssetsLibrary
import AVKit

public class LiveTranscript: NSObject {
    
    var recognitionTask:SFSpeechRecognitionTask?
    var recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
    var audioFormat: AudioStreamBasicDescription?
    var player: AVPlayer?
    var newTranscriptEvent: ((String) -> Void)?
    
    
    var audioFileRef : ExtAudioFileRef?;
    var shouldSaveAudioFile = false;
    var audioFileName : String?;
    
    static let shared = LiveTranscript()
    
    override init()  {
        super.init()
        
    }
    
    
    let tapPrepare: MTAudioProcessingTapPrepareCallback = {
        (tap, itemCount, basicDescription) in
        LiveTranscript.shared.audioFormat = AudioStreamBasicDescription(mSampleRate: basicDescription.pointee.mSampleRate,
                                                                        mFormatID: basicDescription.pointee.mFormatID, mFormatFlags: basicDescription.pointee.mFormatFlags, mBytesPerPacket: basicDescription.pointee.mBytesPerPacket, mFramesPerPacket: basicDescription.pointee.mFramesPerPacket, mBytesPerFrame: basicDescription.pointee.mBytesPerFrame, mChannelsPerFrame: basicDescription.pointee.mChannelsPerFrame, mBitsPerChannel: basicDescription.pointee.mBitsPerChannel, mReserved: basicDescription.pointee.mReserved)
        if LiveTranscript.shared.audioFileRef == nil{
            print("[LiveTranscript] was nil. Creating..." )
            LiveTranscript.shared.createExtAudioFile()
        }else{
            print("[LiveTranscript] was already created" )
        }
    }
    
    
    let tapProcess: MTAudioProcessingTapProcessCallback = {
        (tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut) in
        
        let status_ = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
        if status_ != noErr {
            print("[Transcript] Error TAPGetSourceAudio :\(String(describing: status_.description))")
            return
        }
        
        var sbuf : CMSampleBuffer?
        var status : OSStatus?
        var format: CMFormatDescription?
        
        var formatId =  UInt32(kAudioFormatLinearPCM)
        var formatFlags = UInt32( kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked )
        
        guard var audioFormat = LiveTranscript.shared.audioFormat else {
            return
        }
        
        status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &audioFormat, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        if status != noErr {
            print("[Transcript Live] Error CMAudioFormatDescriptionCreater :\(String(describing: status?.description))")
            return
        }
        
        var timing = CMSampleTimingInfo(duration: CMTimeMake(value: 1, timescale: Int32(audioFormat.mSampleRate)), presentationTimeStamp: LiveTranscript.shared.player!.currentTime(), decodeTimeStamp: CMTime.invalid)
        
        status = CMSampleBufferCreate(allocator: kCFAllocatorDefault,
                                      dataBuffer: nil,
                                      dataReady: Bool(truncating: 0),
                                      makeDataReadyCallback: nil,
                                      refcon: nil,
                                      formatDescription: format,
                                      sampleCount: CMItemCount(UInt32(numberFrames)),
                                      sampleTimingEntryCount: 1,
                                      sampleTimingArray: &timing,
                                      sampleSizeEntryCount: 0, sampleSizeArray: nil,
                                      sampleBufferOut: &sbuf);
        if status != noErr {
            print("[Transcript Live] Error CMSampleBufferCreate :\(String(describing: status?.description))")
            return
        }
        
        status = CMSampleBufferSetDataBufferFromAudioBufferList(sbuf!, blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: bufferListInOut)
        if status != noErr {
            print("[Transcript Live] Error cCMSampleBufferSetDataBufferFromAudioBufferList :\(String(describing: status?.description))")
            return
        }
        
        let currentSampleTime = CMSampleBufferGetOutputPresentationTimeStamp(sbuf!);
        
        print("[Transcript Live] shouldSaveAudioFile \(LiveTranscript.shared.shouldSaveAudioFile)")
        if LiveTranscript.shared.shouldSaveAudioFile{
            // Saving to file...
            print("LiveTranscript.shared.audioFileRef \(LiveTranscript.shared.audioFileRef)")
            if LiveTranscript.shared.audioFileRef != nil {
                status = ExtAudioFileWrite(LiveTranscript.shared.audioFileRef!, UInt32(numberFrames), bufferListInOut)
                if status != noErr {
                    print("[Transcript Live] Error ExtAudioFileWrite :\(String(describing: status?.description))")
                    return
                }
                print("Wrote to audio file")
            }
        } else {
            print("Should not write")
            
        }
        LiveTranscript.shared.recognitionRequest.appendAudioSampleBuffer(sbuf!)
    }
    
    static func getAudioFileCFURL()->CFURL? {
        do{
            let fileManager = FileManager.default
            let documentDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor:nil, create:false)
            let audioFileName = "\(UUID().uuidString).wav"
            LiveTranscript.shared.audioFileName = audioFileName // TODO this should be somewhere else
            let audioFileURL = documentDirectory.appendingPathComponent(audioFileName)
            print("[getAudioFileCFURL] audioFileURL: \(audioFileURL)")
            let cfurl: CFURL = CFBridgingRetain(audioFileURL) as! CFURL;
            return cfurl;
        } catch{
            print("[getAudioFileCFURL] Error :\(error.localizedDescription)")
            return nil
        }
    }
    
    func createExtAudioFile()->OSStatus?
    {
        let cfurl = LiveTranscript.getAudioFileCFURL()
        if cfurl != nil{
            let format = AVAudioFormat(commonFormat: AVAudioCommonFormat.pcmFormatInt16, sampleRate: 44100.0, channels: 1, interleaved: true)
            var status = ExtAudioFileCreateWithURL( cfurl!, kAudioFileWAVEType, (format?.streamDescription)!, nil, AudioFileFlags.eraseFile.rawValue,  &LiveTranscript.shared.audioFileRef)
            if status != noErr {
                print("[Transcript Live] Error tapPrepare ExtAudioFileCreateWithURL :\(String(describing: status.description))")
                return status
            }
            print("Did ExtAudioFileCreateWithURL, gonna set properties...")
            var codecManufacturer = kAppleSoftwareAudioCodecManufacturer
            status =  ExtAudioFileSetProperty(LiveTranscript.shared.audioFileRef!,  kExtAudioFileProperty_CodecManufacturer, UInt32(MemoryLayout<UInt32>.size), &codecManufacturer)
            if status != noErr {
                print("[Transcript Live] Error tapPrepare ExtAudioFileSetProperty kExtAudioFileProperty_CodecManufacturer :\(String(describing: status.description))")
                return status
            }
            status =  ExtAudioFileSetProperty(LiveTranscript.shared.audioFileRef!, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &LiveTranscript.shared.audioFormat)
            if status != noErr {
                print("[Transcript Live] Error tapPrepare ExtAudioFileSetProperty kExtAudioFileProperty_ClientDataFormat:\(String(describing: status.description))")
                return status
            }
            return status
        } else {
            print("[Transcript Live] Error tapPrepare getAudioFileCFURL nil")
            return nil
        }
    }
    
    func restart(_ shouldRestartAudioFile: Bool) {
        print("[TranscriptLive] shouldResetAudioFile: \(shouldRestartAudioFile)")
        if shouldRestartAudioFile {
            LiveTranscript.shared.audioFileRef = nil
        }
        LiveTranscript.shared.shouldSaveAudioFile = true
        if (LiveTranscript.shared.recognitionTask != nil ){
            LiveTranscript.shared.recognitionTask?.cancel()
        }
        LiveTranscript.shared.recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        LiveTranscript.shared.recognitionRequest.shouldReportPartialResults = true
        
        LiveTranscript.shared.recognitionTask = SFSpeechRecognizer()?.recognitionTask(with: self.recognitionRequest, resultHandler: { (result, error) in
            if let error = error {
                NSLog("[Transcription Live] [Error] \(error) desc \(error.localizedDescription)")
            } else {
                NSLog("[Transcription Live] [Result] \(result?.bestTranscription.formattedString)")
                NSLog("[Transcription Live] [Type] Is Final Transcription: \(result?.isFinal)")
                for segment in (result?.bestTranscription.segments ?? []) {
                    NSLog("[Transcription Live] [Segment] Confidence: \(segment.confidence), Timestamp: \(segment.timestamp), Duration: \(segment.duration) \(segment.substring)")
                }
                NSLog("[Transcription Live] [Result] \(result?.bestTranscription.formattedString)")
                guard let sendEvent = self.newTranscriptEvent else { return };
                do {
                    var transcriptionResultData:Dictionary<String, Any> = [
                        "audioFileName": LiveTranscript.shared.audioFileName,
                        "isFinal":  result?.isFinal ?? false,
                        "text": result?.bestTranscription.formattedString ?? "",
                        "content": result?.bestTranscription.segments.map({
                            return [
                                "duration": $0.duration,
                                "confidence": $0.confidence,
                                "text": $0.substring,
                                "startTime": $0.timestamp,
                                "endTime": $0.timestamp + $0.duration
                            ];
                        }) ?? []
                    ];
                    if let theJSONData = try?  JSONSerialization.data(
                        withJSONObject: transcriptionResultData,
                        options: .prettyPrinted
                        ),
                        let theJSONText = String(data: theJSONData,
                                                 encoding: String.Encoding.ascii) {
                        sendEvent(theJSONText)
                    }
                     if result?.isFinal ?? false {
                         print("Result was final")
                     }
                } catch {
                    print(error.localizedDescription)
                }
            }
        })
    }
    
    func finish() {
        LiveTranscript.shared.shouldSaveAudioFile = false
        if (LiveTranscript.shared.recognitionTask != nil ){
            LiveTranscript.shared.recognitionTask?.finish();
        }
    }
    
    // Need to call OSStatus result = ExtAudioFileDispose(extAudioFileRef); to ensure the file not be corrupted
    // via: https://stackoverflow.com/questions/10113977/recording-to-aac-from-remoteio-data-is-getting-written-but-file-unplayable#comment22788263_10129169
    func finishAudioFile()->Bool{
        print("[TranscriptLive] finishAudioFile finishing file")
        if  LiveTranscript.shared.audioFileRef != nil{
            let result : OSStatus = ExtAudioFileDispose(LiveTranscript.shared.audioFileRef!); // check if we should dispose here or on restart, or both
            print("[TranscriptLive] finishAudioFile finished file dispose")
            if result != noErr {
                print("[Transcript Live finish] Error ExtAudioFileDispose :\(String(describing: result.description))")
                return false
            }
            LiveTranscript.shared.recognitionTask != nil
            print("[TranscriptLive] finishAudioFile finished!")
            return true
        } else{
            print("[TranscriptLive] finishAudioFile no file to finish")
            return false
        }
    }
    
    func installTap(player: AVPlayer, newTranscriptEvent: ((String) -> Void)?) {
        LiveTranscript.shared.player = player
        LiveTranscript.shared.newTranscriptEvent = newTranscriptEvent
        guard let playerItem =  player.currentItem else {
            return;
        }
        if (playerItem.asset.tracks(withMediaType: AVMediaType.audio).count > 0 ) {
            
            var callbacks = MTAudioProcessingTapCallbacks(
                version: kMTAudioProcessingTapCallbacksVersion_0,
                clientInfo:nil,
                init: nil,
                finalize: nil,
                prepare: tapPrepare,
                unprepare: nil,
                process: tapProcess)
            
            var tap: Unmanaged<MTAudioProcessingTap>?
            let err = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
            assert(noErr == err);
            
            // let audioTrack = playerItem.tracks.first!.assetTrack!
            
            let audioTrack = playerItem.asset.tracks(withMediaType: AVMediaType.audio).first!
            let inputParams = AVMutableAudioMixInputParameters(track: audioTrack)
            inputParams.audioTapProcessor = tap?.takeRetainedValue()
            
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = [inputParams]
            
            playerItem.audioMix = audioMix
        }
    }
    
}

