//
//  DigitRecognizer.swift
//  NumberPad
//
//  Created by Bridger Maxwell on 9/2/16.
//  Copyright © 2016 Bridger Maxwell. All rights reserved.
//

import Foundation

public struct ImageSize {
    public var width: UInt
    public var height: UInt

    public init(width: UInt, height: UInt) {
        self.width = width
        self.height = height
    }
}

public class DigitRecognizer {
    public typealias DigitStrokes = [[CGPoint]]
    public typealias DigitLabel = String

    public let imageSize = ImageSize(width: 28, height: 28)

    public let labelStringToByte: [DigitLabel : UInt8] = [
        "1" : 1,
        "2" : 2,
        "3" : 3,
        "4" : 4,
        "5" : 5,
        "6" : 6,
        "7" : 7,
        "8" : 8,
        "9" : 9,
        "0" : 0,
        ]

    public lazy var byteToLabelString: [UInt8 : DigitLabel] = {
        var computedByteToLabelString: [UInt8 : DigitLabel] = [:]
        for (label, byte) in self.labelStringToByte {
            computedByteToLabelString[byte] = label
        }
        return computedByteToLabelString
    }()

    public typealias Classification = (Label: DigitLabel, Confidence: CGFloat)
    public func classifyDigit(digit: DigitStrokes) -> Classification? {
        guard let normalizedStroke = DigitRecognizer.normalizeDigit(inputDigit: digit) else {
            fatalError("Could not normalize stroke")
        }
        guard renderToContext(normalizedStrokes: normalizedStroke, size: imageSize, data: dataPointer2) != nil else {
            fatalError("Couldn't render image")
        }

        // Convert the int8 to floats
        let intPointer = dataPointer2.assumingMemoryBound(to: UInt8.self)
        let imageArray = Array<UInt8>(UnsafeBufferPointer(start: intPointer, count: Int(imageSize.width * imageSize.height)))
        for (index, pixel) in imageArray.enumerated() {
            dataBuffer1[index] = Float32(pixel) / 255.0
        }

        BNNSFilterApply(conv1, dataPointer1, dataPointer2)
        BNNSFilterApply(pool1, dataPointer2, dataPointer1)
        BNNSFilterApply(conv2, dataPointer1, dataPointer2)
        BNNSFilterApply(pool2, dataPointer2, dataPointer1)
        BNNSFilterApply(fullyConnected1, dataPointer1, dataPointer2)
        BNNSFilterApply(fullyConnected2, dataPointer2, dataPointer1)

        var highestScore: (Int, Float32)?
        for (index, score) in dataBuffer1[0...9].enumerated() {
            // print("Index \(index) got score \(score)")
            if highestScore?.1 ?? -1 < score {
                highestScore = (index, score)
            }
        }
        if let highestScore = highestScore, let label = byteToLabelString[UInt8(highestScore.0)] {
            print("Higest score index \(highestScore.0) of \(highestScore.1)")
            return (Label: label, Confidence: CGFloat(highestScore.1))
        } else {
            return nil
        }
    }

    public func addStrokeToClassificationQueue(stroke: [CGPoint]) {

    }
    public func recognizeStrokesInQueue() -> [DigitLabel]? {
        return nil
    }

    public class func normalizeDigit(inputDigit: DigitStrokes) -> DigitStrokes? {
        let targetPointCount = 32

        var newInputDigit: DigitStrokes = []
        for stroke in inputDigit {
            // First, figure out the total arc length of this stroke
            var lastPoint: CGPoint?
            var totalDistance: CGFloat = 0
            for point in stroke {
                if let lastPoint = lastPoint {
                    totalDistance += euclidianDistance(a: lastPoint, b: point)
                }
                lastPoint = point
            }
            if totalDistance < 1.0 {
                return nil
            }

            // Now, divide this arc length into 32 segments
            let distancePerPoint = totalDistance / CGFloat(targetPointCount)
            var newPoints: [CGPoint] = []

            lastPoint = nil
            var distanceCovered: CGFloat = 0
            totalDistance = 0
            for point in stroke {
                if let lastPoint = lastPoint {
                    let nextDistance = euclidianDistance(a: lastPoint, b: point)
                    let newTotalDistance = totalDistance + nextDistance
                    while distanceCovered + distancePerPoint < newTotalDistance {
                        distanceCovered += distancePerPoint
                        let ratio: CGFloat = (distanceCovered - totalDistance) / nextDistance
                        if ratio < 0.0 || ratio > 1.0 {
                            print("Uh oh! Something went wrong!")
                        }
                        let newPointX: CGFloat = point.x * ratio + lastPoint.x * (1.0 - ratio)
                        let newPointY: CGFloat = point.y * ratio + lastPoint.y * (1.0 - ratio)
                        newPoints.append(CGPoint(x: newPointX, y: newPointY))
                    }
                    totalDistance = newTotalDistance
                }
                lastPoint = point
            }
            if newPoints.count > 0 && newPoints.count > 29 {
                newInputDigit.append(newPoints)
            } else {
                print("What happened here????")
            }
        }
        let inputDigit = newInputDigit

        var topLeft: CGPoint?
        var bottomRight: CGPoint?
        for stroke in inputDigit {
            for point in stroke {
                if let capturedTopLeft = topLeft {
                    topLeft = CGPoint(x: min(capturedTopLeft.x, point.x), y: min(capturedTopLeft.y, point.y));
                } else {
                    topLeft = point
                }
                if let capturedBottomRight = bottomRight {
                    bottomRight = CGPoint(x: max(capturedBottomRight.x, point.x), y: max(capturedBottomRight.y, point.y));
                } else {
                    bottomRight = point
                }
            }
        }
        let xDistance = (bottomRight!.x - topLeft!.x)
        let yDistance = (bottomRight!.y - topLeft!.y)
        let xTranslate = topLeft!.x + xDistance / 2
        let yTranslate = topLeft!.y + yDistance / 2

        var xScale = 1.0 / xDistance;
        var yScale = 1.0 / yDistance;
        if !xScale.isFinite {
            xScale = 1
        }
        if !yScale.isFinite {
            yScale = 1
        }
        let scale = min(xScale, yScale)

        return inputDigit.map { subPath in
            return subPath.map({ point in
                let x = (point.x - xTranslate) * scale
                let y = (point.y - yTranslate) * scale
                return CGPoint(x: x, y: y)
            })
        }
    }

    let trainedData: UnsafeMutableRawPointer
    let conv1: BNNSFilter
    let pool1: BNNSFilter
    let conv2: BNNSFilter
    let pool2: BNNSFilter
    let fullyConnected1: BNNSFilter
    let fullyConnected2: BNNSFilter

    var dataBuffer1: Array<Float32>
    var dataBuffer2: Array<Float32>
    let dataPointer1: UnsafeMutableRawPointer
    let dataPointer2: UnsafeMutableRawPointer

    public init() {
        let width = Int(imageSize.width)
        let height = Int(imageSize.height)

        var filterParams = createEmptyBNNSFilterParameters();

        let trainedDataPath = Bundle(for: DTWDigitClassifier.self).path(forResource: "trainedData", ofType: "dat")
        let trainedDataLength = 13098536

        // open file descriptors in read-only mode to parameter files
        let data_file = open(trainedDataPath!, O_RDONLY, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH)
        assert(data_file != -1, "Error: failed to open output file at \(trainedDataPath)  errno = \(errno)")

        // memory map the parameters
        trainedData = mmap(nil, trainedDataLength, PROT_READ, MAP_FILE | MAP_SHARED, data_file, 0);

        var input = BNNSImageStackDescriptor(
            width: width,
            height: height,
            channels: 1,
            row_stride: width,
            image_stride: width * height,
            data_type: BNNSDataTypeFloat32,
            data_scale: 1,
            data_bias: 0)

        // ****** conv 1 ******** //

        let conv1Weights = BNNSLayerData(
            data: trainedData + 0,
            data_type: BNNSDataTypeFloat32,
            data_scale: 1,
            data_bias: 0,
            data_table: nil
        )
        let conv1Bias = BNNSLayerData(
            data: trainedData + 3200,
            data_type: BNNSDataTypeFloat32,
            data_scale: 1,
            data_bias: 0,
            data_table: nil
        )

        var conv1_output = BNNSImageStackDescriptor(
            width: width,
            height: height,
            channels: 32,
            row_stride: width,
            image_stride: width * height,
            data_type: BNNSDataTypeFloat32,
            data_scale: 1,
            data_bias: 0)

        var conv1_params = BNNSConvolutionLayerParameters(
            x_stride: 1,
            y_stride: 1,
            x_padding: 2,
            y_padding: 2,
            k_width: 5,
            k_height: 5,
            in_channels: input.channels,
            out_channels: conv1_output.channels,
            weights: conv1Weights,
            bias: conv1Bias,
            activation: BNNSActivation(
                function: BNNSActivationFunctionRectifiedLinear,
                alpha: 0,
                beta: 0
            )
        )

        conv1 = BNNSFilterCreateConvolutionLayer(&input, &conv1_output, &conv1_params, &filterParams)!

        // ****** pool 1 ******** //

        let pool1Data = BNNSLayerData(
            data: nil,
            data_type: BNNSDataTypeFloat32,
            data_scale: 1,
            data_bias: 0,
            data_table: nil
        )

        var pool1_output = BNNSImageStackDescriptor(
            width: width / 2,
            height: height / 2,
            channels: 32,
            row_stride: width / 2,
            image_stride: (width / 2) * (height / 2),
            data_type: BNNSDataTypeFloat32,
            data_scale: 1,
            data_bias: 0)

        var pool1_parameters = BNNSPoolingLayerParameters(
            x_stride: 2,
            y_stride: 2,
            x_padding: 0,
            y_padding: 0,
            k_width: 2,
            k_height: 2,
            in_channels: 32,
            out_channels: 32,
            pooling_function: BNNSPoolingFunctionMax,
            bias: pool1Data,
            activation: BNNSActivation(
                function: BNNSActivationFunctionIdentity,
                alpha: 0,
                beta: 0
            )
        )

        pool1 = BNNSFilterCreatePoolingLayer(&conv1_output, &pool1_output, &pool1_parameters, &filterParams)!

        // ****** conv 2 ******** //

        let conv2Weights = BNNSLayerData(
            data: trainedData + 3328,
            data_type: BNNSDataTypeFloat32,
            data_scale: 1,
            data_bias: 0,
            data_table: nil
        )
        let conv2Bias = BNNSLayerData(
            data: trainedData + 208128,
            data_type: BNNSDataTypeFloat32,
            data_scale: 1,
            data_bias: 0,
            data_table: nil
        )

        var conv2_output = BNNSImageStackDescriptor(
            width: width / 2,
            height: height / 2,
            channels: 64,
            row_stride: width / 2,
            image_stride: (width / 2) * (height / 2),
            data_type: BNNSDataTypeFloat32,
            data_scale: 1,
            data_bias: 0)

        var conv2_parameters = BNNSConvolutionLayerParameters(
            x_stride: 1,
            y_stride: 1,
            x_padding: 2,
            y_padding: 2,
            k_width: 5,
            k_height: 5,
            in_channels: pool1_output.channels,
            out_channels: conv2_output.channels,
            weights: conv2Weights,
            bias: conv2Bias,
            activation: BNNSActivation(
                function: BNNSActivationFunctionRectifiedLinear,
                alpha: 0,
                beta: 0
            )
        )

        conv2 = BNNSFilterCreateConvolutionLayer(&pool1_output, &conv2_output, &conv2_parameters, &filterParams)!

        // ****** pool 2 ******** //

        let pool2Data = BNNSLayerData(
            data: nil,
            data_type: BNNSDataTypeFloat32,
            data_scale: 1,
            data_bias: 0,
            data_table: nil
        )

        var pool2_output = BNNSImageStackDescriptor(
            width: width / 4,
            height: height / 4,
            channels: 64,
            row_stride: width / 4,
            image_stride: (width / 4) * (height / 4),
            data_type: BNNSDataTypeFloat32,
            data_scale: 1,
            data_bias: 0)

        var pool2_parameters = BNNSPoolingLayerParameters(
            x_stride: 2,
            y_stride: 2,
            x_padding: 0,
            y_padding: 0,
            k_width: 2,
            k_height: 2,
            in_channels: conv2_output.channels,
            out_channels: pool2_output.channels,
            pooling_function: BNNSPoolingFunctionMax,
            bias: pool2Data,
            activation: BNNSActivation(
                function: BNNSActivationFunctionIdentity,
                alpha: 0,
                beta: 0
            )
        )

        pool2 = BNNSFilterCreatePoolingLayer(&conv2_output, &pool2_output, &pool2_parameters, &filterParams)!

        // ****** fully connected 1 ******** //

        var fullyConnected_in = BNNSVectorDescriptor(
            size: pool2_output.width * pool2_output.height * pool2_output.channels,
            data_type: BNNSDataTypeFloat32,
            data_scale: 1,
            data_bias: 0)

        var fullyConnected_out = BNNSVectorDescriptor(
            size: 1024,
            data_type: BNNSDataTypeFloat32,
            data_scale: 1,
            data_bias: 0)

        let fullyConnected1Weights = BNNSLayerData(
            data: trainedData + 208384,
            data_type: BNNSDataTypeFloat32,
            data_scale: 1,
            data_bias: 0,
            data_table: nil
        )

        let fullyConnected1Bias = BNNSLayerData(
            data: trainedData + 13053440,
            data_type: BNNSDataTypeFloat32,
            data_scale: 1,
            data_bias: 0,
            data_table: nil
        )

        var fullyConnected1_params = BNNSFullyConnectedLayerParameters(
            in_size: fullyConnected_in.size,
            out_size: fullyConnected_out.size,
            weights: fullyConnected1Weights,
            bias: fullyConnected1Bias,
            activation: BNNSActivation(
                function: BNNSActivationFunctionRectifiedLinear,
                alpha: 0,
                beta: 0
        ))

        fullyConnected1 = BNNSFilterCreateFullyConnectedLayer(&fullyConnected_in, &fullyConnected_out, &fullyConnected1_params, &filterParams)!

        // ****** fully connected 1 ******** //

        var output = BNNSVectorDescriptor(
            size: 10,
            data_type: BNNSDataTypeFloat32,
            data_scale: 1,
            data_bias: 0)

        let fullyConnected2Weights = BNNSLayerData(
            data: trainedData + 13057536,
            data_type: BNNSDataTypeFloat32,
            data_scale: 1,
            data_bias: 0,
            data_table: nil
        )

        let fullyConnected2Bias = BNNSLayerData(
            data: trainedData + 13098496,
            data_type: BNNSDataTypeFloat32,
            data_scale: 1,
            data_bias: 0,
            data_table: nil
        )

        var fullyConnected2_params = BNNSFullyConnectedLayerParameters(
            in_size: fullyConnected_out.size,
            out_size: output.size,
            weights: fullyConnected2Weights,
            bias: fullyConnected2Bias,
            activation: BNNSActivation(
                function: BNNSActivationFunctionIdentity,
                alpha: 0,
                beta: 0
        ))

        fullyConnected2 = BNNSFilterCreateFullyConnectedLayer(&fullyConnected_out, &output, &fullyConnected2_params, &filterParams)!

        dataBuffer1 = Array<Float32>(repeating: 0, count: 6272)
        dataBuffer2 = Array<Float32>(repeating: 0, count: 25088)

        dataPointer1 = UnsafeMutableRawPointer(mutating: dataBuffer1)
        dataPointer2 = UnsafeMutableRawPointer(mutating: dataBuffer2)
    }
}
