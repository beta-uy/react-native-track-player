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


public class LiveTranscript: NSObject {
    
    var recognitionTask:SFSpeechRecognitionTask?
    var recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
    var audioFormat: AudioStreamBasicDescription?
    var player: AVPlayer?
    var newTranscriptEvent: ((String) -> Void)?
    
    static let shared = LiveTranscript()
    
    override init()  {
        super.init()
    }
    
    
    let tapPrepare: MTAudioProcessingTapPrepareCallback = {
        (tap, itemCount, basicDescription) in
        LiveTranscript.shared.audioFormat = AudioStreamBasicDescription(mSampleRate: basicDescription.pointee.mSampleRate,
                                                                        mFormatID: basicDescription.pointee.mFormatID, mFormatFlags: basicDescription.pointee.mFormatFlags, mBytesPerPacket: basicDescription.pointee.mBytesPerPacket, mFramesPerPacket: basicDescription.pointee.mFramesPerPacket, mBytesPerFrame: basicDescription.pointee.mBytesPerFrame, mChannelsPerFrame: basicDescription.pointee.mChannelsPerFrame, mBitsPerChannel: basicDescription.pointee.mBitsPerChannel, mReserved: basicDescription.pointee.mReserved)
    }
    
    let tapProcess: MTAudioProcessingTapProcessCallback = {
        (tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut) in
        //        print("[Transcript] callback \(tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut)\n")
        
        
        
        let status_ = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
        //print("get audio: \(status)\n")
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
        LiveTranscript.shared.recognitionRequest.appendAudioSampleBuffer(sbuf!)
    }
    
    
    func restart() {
        if (LiveTranscript.shared.recognitionTask != nil ){
            LiveTranscript.shared.recognitionTask?.cancel()
        }
        LiveTranscript.shared.recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        LiveTranscript.shared.recognitionRequest.shouldReportPartialResults = true
        LiveTranscript.shared.recognitionTask = SFSpeechRecognizer()?.recognitionTask(with: self.recognitionRequest, resultHandler: { (result, error) in
            
            

            if let error = error {
                NSLog("[Transcription Live] [Error] \(error) desc \(error.localizedDescription)")
//                LiveTranscript.shared.restart()
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
                    
                } catch {
                    print(error.localizedDescription)
                }
                
                
            }
            
        })
    }
    
    func finish() {
        if (LiveTranscript.shared.recognitionTask != nil ){
            LiveTranscript.shared.recognitionTask?.finish();
        }
    }
    
    func installTap(player: AVPlayer, newTranscriptEvent: ((String) -> Void)?) {
        LiveTranscript.shared.player = player
        LiveTranscript.shared.newTranscriptEvent = newTranscriptEvent
        let playerItem = player.currentItem!
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
