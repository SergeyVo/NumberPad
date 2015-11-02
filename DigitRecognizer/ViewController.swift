//
//  ViewController.swift
//  NumberPad
//
//  Created by Bridger Maxwell on 12/13/14.
//  Copyright (c) 2014 Bridger Maxwell. All rights reserved.
//

import UIKit
import DigitRecognizerSDK

class Stroke {
    var points: [CGPoint] = []
    var layer: CAShapeLayer
    
    init(){
        layer = CAShapeLayer()
        layer.strokeColor = UIColor.blackColor().CGColor
        layer.lineWidth = 2
        layer.fillColor = nil
    }
    
    func addPoint(point: CGPoint)
    {
        points.append(point)
        
        let path = CGPathCreateMutable()
        for (index, point) in points.enumerate() {
            if index == 0 {
                CGPathMoveToPoint(path, nil, point.x, point.y)
            } else {
                CGPathAddLineToPoint(path, nil, point.x, point.y)
            }
        }
        layer.path = path;
    }
}

class ViewController: UIViewController, UIGestureRecognizerDelegate {
    var scrollView: UIScrollView!
    var currentStroke: Stroke?
    var previousStrokes: [Stroke] = []
    var digitClassifier: DTWDigitClassifier!
    @IBOutlet weak var labelSelector: UISegmentedControl!
    @IBOutlet weak var resultLabel: UILabel!
    
    required init(coder aDecoder: NSCoder) {
        self.digitClassifier = DTWDigitClassifier()
        super.init(coder: aDecoder)!
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.digitClassifier = AppDelegate.sharedAppDelegate().digitClassifier
        self.scrollView = UIScrollView(frame: self.view.bounds)
        self.scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        self.view.insertSubview(self.scrollView, atIndex: 0)
        
        let strokeRecognizer = StrokeGestureRecognizer()
        self.scrollView.addGestureRecognizer(strokeRecognizer)
        strokeRecognizer.addTarget(self, action: "handleStroke:")
        
        for index in 0..<self.labelSelector.numberOfSegments {
            if self.labelSelector.titleForSegmentAtIndex(index) == "Test" {
                self.labelSelector.selectedSegmentIndex = index
                break;
            }
        }
    }
    
    func handleStroke(recognizer: StrokeGestureRecognizer) {
        if recognizer.state == UIGestureRecognizerState.Began {
            self.currentStroke = Stroke()
            self.scrollView.layer.addSublayer(self.currentStroke!.layer)
            
            let point = recognizer.locationInView(self.scrollView)
            self.currentStroke!.addPoint(point)
            self.resultLabel.text = ""
            
        } else if recognizer.state == UIGestureRecognizerState.Changed {
            if let currentStroke = self.currentStroke {
                let point = recognizer.locationInView(self.scrollView)
                currentStroke.addPoint(point)
            }
        } else if recognizer.state == UIGestureRecognizerState.Ended {
            if let currentStroke = self.currentStroke {
                
                var wasFarAway = false
                if let lastStroke = self.previousStrokes.last {
                    if let lastStrokeLastPoint = lastStroke.points.last {
                        let point = recognizer.locationInView(self.scrollView)
                        if euclidianDistance(lastStrokeLastPoint, b: point) > 150 {
                            wasFarAway = true
                        }
                    }
                }
                
                let selectedSegment = self.labelSelector.selectedSegmentIndex
                if selectedSegment != UISegmentedControlNoSegment {
                    if let currentLabel = self.labelSelector.titleForSegmentAtIndex(selectedSegment) {
                        
                        if currentLabel == "Test" {
                            var allStrokes: DTWDigitClassifier.DigitStrokes = []
                            if !wasFarAway {
                                for previousStroke in self.previousStrokes {
                                    allStrokes.append(previousStroke.points)
                                }
                            }
                            allStrokes.append(currentStroke.points)
                            
                            if let writtenNumber = self.readStringFromStrokes(allStrokes) {
                                self.resultLabel.text = writtenNumber
                            } else {
                                self.resultLabel.text = "Unknown"
                            }
                            if wasFarAway {
                                self.clearStrokes(nil)
                            }
                            
                        } else {
                            if previousStrokes.count > 0 && wasFarAway {
                                var lastDigit: DTWDigitClassifier.DigitStrokes = []
                                for previousStroke in self.previousStrokes {
                                    lastDigit.append(previousStroke.points)
                                }
                                self.clearStrokes(nil)
                                
                                self.digitClassifier.learnDigit(currentLabel, digit: lastDigit)
                                if let classification = self.digitClassifier.classifyDigit(lastDigit) {
                                    self.resultLabel.text = classification.Label
                                } else {
                                    self.resultLabel.text = "Unknown"
                                }
                            }
                        }
                    }
                }
                
                previousStrokes.append(self.currentStroke!)
            }
        }
    }
    
    // If any one stroke can't be classified, this will return nil
    func readStringFromStrokes(strokes: [[CGPoint]]) -> String? {
        if let classifiedLabels = self.digitClassifier.classifyMultipleDigits(strokes) {
            return classifiedLabels.reduce("", combine: +)
        } else {
            return nil
        }
    }
    
    
    @IBAction func clearStrokes(sender: AnyObject?) {
        for previousStroke in self.previousStrokes {
            previousStroke.layer.removeFromSuperlayer()
        }
        self.previousStrokes.removeAll(keepCapacity: false)
    }
}

