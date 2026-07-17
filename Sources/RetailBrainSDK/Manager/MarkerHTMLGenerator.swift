//
//  MarkerHTMLGenerator.swift
//  RetailBrainSDK
//
//  Created by ajith.a.s on 02/07/26.
//

import Foundation

public class MarkerHTMLGenerator {
    
    public static func customDestinationMarkerHTML(
        imageSrc: String,
        destinationId: String,
        color: String = "#000000"
    ) -> String {
        return """
        <div style="width:45px;height:57px;position:relative;">
            <svg
                xmlns="http://www.w3.org/2000/svg"
                xmlns:xlink="http://www.w3.org/1999/xlink"
                width="45"
                height="57"
                viewBox="0 0 79 91"
                preserveAspectRatio="xMidYMid meet"
                style="position:absolute; left:0; top:-28.5px;">
        
                <path
                    d="M59.609,57.75C71.947,45.453 71.98,25.482 59.683,13.144C47.386,0.805 27.415,0.772 15.077,13.069C2.739,25.366 2.705,45.337 15.002,57.675L27.907,70.624C33.077,75.811 41.473,75.825 46.66,70.655L59.609,57.75Z"
                    fill="\(color)" />
        
                <path
                    d="M59.329,13.496C47.227,1.354 27.573,1.321 15.43,13.423C3.287,25.525 3.254,45.179 15.356,57.322L28.261,70.27C33.236,75.262 41.315,75.276 46.307,70.301L59.255,57.396C71.398,45.294 71.431,25.639 59.329,13.496Z"
                    fill="none"
                    stroke="#FFFFFF"
                    stroke-width="1"/>
        
                <clipPath id="cp\(destinationId)">
                    <circle
                        cx="37.3"
                        cy="35.4"
                        r="24"/>
                </clipPath>
        
                <image
                    href="\(imageSrc)"
                    x="13.3"
                    y="11.4"
                    width="48"
                    height="48"
                    clip-path="url(#cp\(destinationId))"/>
        
                <path
                    d="M37.301,85.867m-4.5,0a4.5,4.5 0,1 1,9 0a4.5,4.5 0,1 1,-9 0"
                    fill="#FFFFFF"
                    stroke="\(color)"
                    stroke-width="1"/>
        
            </svg>
        </div>
        """
    }
    
    public static func startMarkerHTML(
        title: String,
        subtitle: String?,
        color: String,
        compact: Bool = false
    ) -> String {
        let gap = compact ? 4 : 6
        let paddingY = compact ? 2 : 4
        let paddingX = compact ? 6 : 8
        let fontSize = compact ? 11 : 12
        let badgeSize = compact ? 18 : 20
        let borderRadius = compact ? 12 : 14
        
        let subtitleHTML = subtitle.map { "<span>\($0)</span>" } ?? ""
        
        return """
        <div style="
            display: inline-flex;
            align-items: center;
            gap: \(gap)px;
            background: white;
            border: 2px solid \(color);
            border-radius: \(borderRadius)px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.2);
            color: #111827;
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            font-size: \(fontSize)px;
            font-weight: 600;
            padding: \(paddingY)px \(paddingX)px;
            white-space: nowrap;
        ">
            <span style="
                align-items: center;
                background: \(color);
                border-radius: 50%;
                color: white;
                display: inline-flex;
                height: \(badgeSize)px;
                justify-content: center;
                min-width: \(badgeSize)px;
            ">\(title)</span>
            \(subtitleHTML)
        </div>
        """
    }
}
