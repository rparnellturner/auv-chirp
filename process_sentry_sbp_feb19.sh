#!/bin/bash

##############################################################################

# SCRIPT TO CONVERT NAVIGATED EDGETECH JSF FORMAT FILES TO SEGY AND PLOT

# SHOULD BE RUN IN SSS-SBP DIRECTORY, WHICH SHOULD CONTAIN THE NAV_INJECTOR*.NAV FILE, 
# A DIRECTORY CONTAINING NAVIGATED JSF FILES (E.G. /PROC OR /NAV), AND THIS SCRIPT

# REQUIREMENTS (version used in testing):
#  MB-SYSTEM (5.0)
#  GMT (5.4.4) 
#  SEISMIC UNIX (release 43R5)

# ROSS PARNELL-TURNER, IGPP / SCRIPPS INSTITUTION OF OCENANOGRAPHY 
# RPARNELLTURNER@UCSD.EDU
# NSF GRANT NUMBER: OCE-1754419
# FEBRUARY 2019

# TO BE ADDED
# - STATIC CORRECTION ROUTINE
# - INTERPRETATION IMPORT

##############################################################################

# SET SOME GMT DEFAULTS

gmtset PS_PAGE_ORIENTATION portrait  FONT_ANNOT_PRIMARY 8  FONT_ANNOT_SECONDARY 6  FONT_TITLE 10 FONT_LABEL 10 MAP_LABEL_OFFSET 0.2c  MAP_ANNOT_OFFSET_PRIMARY 0.1c MAP_ANNOT_OFFSET_SECONDARY 0.1c PS_MEDIA a0 MAP_TICK_LENGTH 0.1 PS_LINE_CAP round FORMAT_FLOAT_OUT %12.10f FORMAT_GEO_MAP ddd:mm.xx MAP_FRAME_TYPE plain PS_LINE_JOIN round 

# # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # 

#  ENTER VARIABLES HERE

# Sentry dive number
dive=520

# directory containing jsf files
jsf_dir=proc

# location of underlay bathymetry grid (do not include *.grd ending)
grid=../multibeam/sentry520_20181207_1243_rnv_tide_1.00x1.00_BV04_thresholded

# set start and end times for SBP plot in seconds  TWTT relative to vehicle
t1=0.07
t2=0.15

# velocity for scaling depth axis (tyipcally water velocity ~ 1500 m/s for thin sediments)
v=1500

# plotting options for basemap
bval="-Bxya0.5mf.1m -BsWNe"
plotwidth=16

# plotting options for CHIRP sections:
# height of plots in cm
chirpheight=6
#  horizontal scale, cm per cdp
horiz_scale=0.01

# variables to break dive into separate survey lines: 
# dcog: first differential of course over ground (i.e. heading)
# cdpmin: minimum length of an individual line in common depth points (cdps)

dcog=0.5
cdpmin=50

#  SWITCHES: 0 is off, 1 is on
#  suggest completing one step at a time and verifying results before moving to next

# 1. convert navigated jsf files to segy and SU format
extractjsf=0
# 2. get navigation info,  identify individual lines, plot QC map
getnav=0
# 3. divide CHIRP data into individual lines
getsufiles=0
# 4. plot a basemap showing multibeam bathymetry and processed CHIRP lines
plotbasemap=0
# 5. make GMT-friendly NetCDF grid files for plotting
makegrid=1
# 6. plot individual profiles
plotgrid=1
# 7. show gridded CHIRP profiles as they are plotted; 1 = on, 0 = off (will fill screen with plots if switched on)
showplots=1


# # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # 

proj=-JM$plotwidth
rgn=`grdinfo -I- $grid.grd`

jsf_start=`ls -1 $jsf_dir\/*.jsf | sed 's/[^0-9]*//g' | head -1`
jsf_end=`ls -1 $jsf_dir\/*.jsf | sed 's/[^0-9]*//g' | tail -1`

# make some directories

if [ ! -d "su_files" ]; then
	mkdir su_files
fi

if [ ! -d "images" ]; then
	mkdir images
fi

divedate=`awk -F, '{print $1}' nav_injector_sentry$dive_*.nav | sed -e 's/\//\-/g' | head -1 `
echo Sentry $dive $divedate


# # # # # # # # # # # # # # # # # # # # # # # # # # # 

if [ $extractjsf -eq 1 ] ; then

	echo "converting navigated jsf files to segy and SU format"

	# make list of jsf files to be processed, count them up
	ls -1  $jsf_dir\/*.jsf > jsflist
	numjsf=`wc -l jsflist | awk '{print $1}'`
 
 	echo "extracting $numjsf jsf files, Sentry $dive"
 
	# FIRST MAKE A LIST OF ALL JSF FILES TO BE PROCESSED
	# THEN USE MB-SYSYEM TO EXTRACT SEGY FILES FROM JSF

	for file in `seq 1 1 $numjsf  `; do
	
	filename=`awk 'NR==file {print $1 }' file=$file jsflist `
	echo $filename
		echo $filename > datalist.mb-1
		mbextractsegy -Idatalist.mb-1 -O$filename\.segy
	done

	# CREATE SU FILES FROM SEGY FILES FOR PROCESSING IN SU
	echo $jsf_dir
	for file in `seq 1 1 $numjsf `; do
		filename=`awk 'NR==file {print $1 }' file=$file jsflist `
		shortfilename=`awk 'NR==file {print $1 }' file=$file jsflist | sed "s/$jsf_dir\\///g" `
		segyread tape=$filename\.segy endian=0 verbose=1 | \
		segyclean > su_files/sentry$dive\-$shortfilename\.su
		done		

	# MAKE SINGLE SU FILE FOR ALL LINES

	cat su_files/sentry$dive-*.su > su_files/sentry$dive\_all.su
		
	# get day, hour, minute, second, cdp, x, y from su header (note xy units are arc seconds*100, not accurate enough...)

	cat su_files/sentry$dive\_all.su | sugethw output=geom key=day,hour,minute,sec,cdp,sx,sy  > sentry$dive\_all.xy

fi

 
# # # # # # # # # # # # # # # # # # # # # # # # # # # 


if [ $getnav -eq 1 ] ; then

	echo "getting navigation info"

	# find julian day of dive from date 

	jday=`echo  $divedate | xargs date -j -f "%m-%d-%Y" "+%j" `
	echo Julian day: $jday

	#  get times and trace numbers, convert to lat lon (not very accurate, but won't be using for anything )

	awk ' $6!=0 && $7!=0 {printf "%i%02d%02d%02d %12.8f %12.8f %i\n", $1, $2, $3, $4, $6/360000, $7/360000, $5}' sentry$dive\_all.xy > sentry$dive\_all_jday_traces.xy

	# get lat lon heading and julian day hr min sec from nav injector file

	cat nav_injector_sentry$dive_2018*.nav  | sed s/'\/'/','/g | sed s/':'/','/g | sed s/,/\ /g  | \
	 awk  'NR%10==0 {print jday$4$5substr($6,1,2), $7, $8, $9, $10, $11, $12, $13}' jday=$jday |\
	 awk '!($1 in a) {a[$1];print}' | filter1d -FP10 |\
	 awk '{printf "%i %14.10f %14.10f %5.2f %6.4f\n", $1, $2, $3, (($4-180)*($4-180))**0.5, $8}'>  nav_injector_sentry$dive\_nav_jday_onesec.xy
	 
	# join with trace number from su file, using (julian day, hr, min, sec) as index; resample, calculate derivative of heading to identify turns
	join  sentry$dive\_all_jday_traces.xy nav_injector_sentry$dive\_nav_jday_onesec.xy   | tee temp222 |  awk 'NR%1==0 {print $4, $3, $2, $7, ($7-b)/(NR-a);a=NR;b=$7}'  > sentry$dive\_all_jday_traces_injector_join.xy
	 
	# apply boxcar filter to cog, then calculate second derivative, then apply Maximum likelihood probability filter to remove outliers
	 awk '{print $1, $4}' sentry$dive\_all_jday_traces_injector_join.xy | filter1d -Fg200 -E | awk '{print $1, $2, ($2-b)/(NR-a);a=NR;b=$2}' | awk '{print $1, $2, $3, ($3-b)/(NR-a);a=NR;b=$3}' | filter1d -FP100 -E > temp333


	# get cdp, lat lon, unfiltered heading from nav injector
	awk '{print $1, $2, $3, $4}'  sentry$dive\_all_jday_traces_injector_join.xy > temp444

	# rejoin filtered cog values with geometry
 	paste temp444 temp333 | awk '!($1 in a) {a[$1];print}' > sentry$dive\_heading.xy

	# select points where derivative of cog is greater than dcog, and remove repeated points assuming that each line needs to be > cdpmin cdps long
		
	makecpt -T-10/10/1 -Cseis -Z > dcog.cpt
	
	echo "dividing dive into individual lines"

	awk '$7>dcog || $7<-dcog   {print $3, $2, $1, $4, $7, ($1-a);a=$1  }' dcog=$dcog sentry$dive\_heading.xy | awk '$6>cdpmin {print $0}' cdpmin=$cdpmin >   sentry$dive\_turns.xy 
    tail -1  sentry$dive\_heading.xy | awk  '{print $3, $2, $1, $4, $7   }' >>   sentry$dive\_turns.xy 
	
	# plot turning points = line joins 
	
	echo "plotting nav QC map"

	 psxy  sentry$dive\_turns.xy  -Sc.3 -W1,black $rgn $proj -B0 -K -Bxya.2mf.1m -BSWne -Y3 -X3 > sentry$dive\_checklinegeom.ps

	makecpt -T0/180/5 -Z -Cseis > hdg.cpt
		
	# plot heading as colored dots
	awk '  {print $3, $2, $4 }' sentry$dive\_all_jday_traces_injector_join.xy | psxy  -Chdg.cpt -Sc.05  $rgn $proj -B0 -O -K >> sentry$dive\_checklinegeom.ps

	
	# make file with line start stop index 
	
	rm -f linestartsends temp; touch linestartsends temp
	numlines=`wc -l sentry$dive\_turns.xy | awk '{print $1-1}'`
	echo number of lines = $numlines
	for line in `seq 1 1 $numlines` ; do
		line2=`echo $line | awk '{print $1+1}' `
		startcdp=`awk 'NR==line {printf "%i\n", $3}' line=$line sentry$dive\_turns.xy`
		startlon=`awk 'NR==line {printf "%12.8f\n", $1}' line=$line sentry$dive\_turns.xy`
		startlat=`awk 'NR==line {printf "%12.8f\n", $2}' line=$line sentry$dive\_turns.xy`

		fincdp=`awk 'NR==line2 {printf "%i\n", $3}' line2=$line2 sentry$dive\_turns.xy`
		finlon=`awk 'NR==line2 {printf  "%12.8f\n", $1}' line2=$line2 sentry$dive\_turns.xy`
		finlat=`awk 'NR==line2 {printf  "%12.8f\n", $2}' line2=$line2 sentry$dive\_turns.xy`

		echo $line $startlon $startlat >> temp
		echo $line $finlon $finlat >> temp

		# calculate length of each line in meters

		length=`awk '$1==line {print $2, $3, $1}' line=$line temp | mapproject -Ge- | awk 'NR%2==0 {printf "%i", $4} '`

		echo $line $startcdp $fincdp $startlon $startlat $finlon $finlat $length >> linestartsends
		echo line $line cdp_start $startcdp cdp_end $fincdp
	
	done
		
	psscale -D1.5/-.8/3/.15h -Ba90g900f30/:"COG":   -Chdg.cpt -O  -K   >> sentry$dive\_checklinegeom.ps

	psbasemap $rgn $proj -B0 -O -K >> sentry$dive\_checklinegeom.ps
	
	 pstext -JX$plotwidth -R0/10/0/10 -Gwhite   -F+jLB+f10,0,black   -N    -K   -O << EOF >> sentry$dive\_checklinegeom.ps
.1 .1 Sentry $dive
EOF

	awk '{print $4, $5, $1}' linestartsends | gmt pstext -F+jLB+a30+f8,0,black -G255 -TO -D.1/.1+v.5,gray  $rgn $proj -K -O -N >>  sentry$dive\_checklinegeom.ps



	# plot heading vs CDP

	cdpmin=`awk '{print $2-2000} ' linestartsends | head -1`
	cdpmax=`awk '{print $3+2000} ' linestartsends | tail -1`

	offset=`echo $plotwidth | awk '{print $1+2}'`
	awk '{print $1, $4, $4}' sentry$dive\_heading.xy   | psxy -Sc.03 -Chdg.cpt  -R$cdpmin\/$cdpmax\/-5/180 -JX$plotwidth\/5  -Bxa10000f5000+lCDP  -Bya30f15+lCOG    -BSEn -O  -K  -X$offset >> sentry$dive\_checklinegeom.ps	

	# plot turning points = line joins 
	awk '{print $3, $5}' sentry$dive\_turns.xy | psxy -Sc.3 -W1,black  -R$cdpmin\/$cdpmax\/-1.5/1.5 -JX$plotwidth\/5   -O  -K  >> sentry$dive\_checklinegeom.ps	
	awk '{print $3, $5, NR}' sentry$dive\_turns.xy |  gmt pstext -F+jLB+a30+f8,0,black -G255 -TO -D.1/.1+v.5,gray  -R$cdpmin\/$cdpmax\/-1.5/1.5 -JX$plotwidth\/5 -K -O -N >>  sentry$dive\_checklinegeom.ps

	# plot dcog cutoff value

	echo $cdpmin $dcog > temp
	echo $cdpmax $dcog >> temp

	gmt psxy -W.5,black,-  -R$cdpmin\/$cdpmax\/-1.5/1.5 -JX$plotwidth\/5    -K  -O  << EOF >> sentry$dive\_checklinegeom.ps
$cdpmin $dcog
$cdpmax $dcog
>
$cdpmin -$dcog
$cdpmax -$dcog
EOF
 	
	# first deriv of heading
	awk '{print $1, $7}' sentry$dive\_heading.xy | filter1d -FP100 | psxy -Sc.03 -Gblack  -R$cdpmin\/$cdpmax\/-1.5/1.5 -JX$plotwidth\/5  -Bxa10000f5000+lCDP  -Bya.5f.1+ldCOG -BSWn -O    >> sentry$dive\_checklinegeom.ps	


	psconvert -A -Tg -Qt -Qg sentry$dive\_checklinegeom.ps
	open sentry$dive\_checklinegeom.png

fi




# # # # # # # # # # # # # # # # # # # # # # # # # # # 


if [ $getsufiles -eq 1 ] ; then

	echo "dividing CHRIP data into individual lines"

	numlines=`wc -l sentry$dive\_turns.xy | awk '{print $1-1}'`

	for line in `seq 1 1 $numlines` ; do
		 echo line $line started 

		cdp1=`awk '$1==line {print $2}' line=$line linestartsends `
		cdp2=`awk '$1==line {print $3}' line=$line linestartsends `

		cdpnum=`echo $cdp2 $cdp1 | awk '{print ($1-$2)+1}' `
		
		# select cdps for individual line; apply time window; apply gain function; balance traces; clip outliers; apply filter; fix headers

		cat su_files/sentry$dive\_all.su |\
		suwind tmin=$t1 tmax=$t2 key=tracl min=$cdp1 max=$cdp2 |\
		sugain tpow=1 qbal=1 qclip=.99  | \
		sufilter f=200,250,50000,80000  | \
		sushw key=tracr a=1 c=.016 j=1   | \
		sushw key=cdp a=1 c=.016 j=1     | \
		sushw key=tracl a=1 c=.016 j=1   | \
		sushw key=fldr a=1 c=.016 j=1   > su_files/sentry$dive\_line$line\_filt.su
		echo line $line complete 

 	done
fi

 # # # # # # # # # # # # # # # # # # # # # # # # # # 

if [ $plotbasemap -eq 1 ] ; then

	echo "plotting basemap showing multibeam bathymetry and processed CHIRP lines"


	outfile=sentry$dive\_basemap

	# CALCUATE A SLOPE GRID FOR ILLUMINATION
	grdgradient $grid.grd -fg -D -S$grid.temp.grd -Gjunk.grd
	# CONVERT TO DEGREES, WRITE OUT XYZ FILES
	grdmath $grid.temp.grd ATAN PI DIV 180 MUL -0.01 MUL = $grid.slope.grd
	rm -f $grid.temp.grd

	psbasemap  $bval $rgn $proj -K -X2 -Y2 > $outfile.ps

	grd2cpt $grid.grd -Chaxby  -E > $grid.cpt

	grdimage $grid.grd -I$grid.slope.grd -C$grid.cpt $bval $rgn $proj -K -O -Q >> $outfile.ps

	gmt pstext -JX8 -R0/10/0/10 -Gwhite   -F+jLB+f8,0,black   -N    -K   -O << EOF >> $outfile.ps
.1 0.3 Sentry $dive
EOF

	awk '{print $4, $5}' linestartsends | psxy   -Sc.1 -Gred -W.3,black $rgn $proj -K -O >> $outfile.ps
	awk ' {print $3, $2 }' sentry$dive\_all_jday_traces_injector_join.xy | psxy  -W.5,black  $rgn $proj -K  -O >> $outfile.ps

	numlines=`wc -l sentry$dive\_turns.xy | awk '{print $1-1}'`
	for line in `seq 1 1 $numlines` ; do
		cdp1=`awk '$1==line {print $2}' line=$line linestartsends`
		cdp2=`awk '$1==line {print $3}' line=$line linestartsends`
		
		awk ' $1>cdp1 && $1<=cdp2 {print $3, $2, $1}' cdp1=$cdp1 cdp2=$cdp2 sentry$dive\_all_jday_traces_injector_join.xy |\
		awk '!($3 in a) {a[$3];print}' | sample1d -T2 -I1 | awk 'NR%500==0 {print $0}' | psxy -Sc.05 -Gblack -W.3,black $rgn $proj -O -K >> $outfile.ps
	done

	awk '{print $4, $5, $1}' linestartsends | gmt pstext -F+jLB+a30+f5,0,black -G255 -TO -D.1/.1+v.5,gray  $rgn $proj -K -O -N >> $outfile.ps



	pslegend $proj $rgn  -Dx5.5/-.4/1.0i/0.075i/BL   -O  -K   << EOF >> $outfile.ps
M -104 9.8 0.5+l+ar f 
EOF

	psscale -D1.5/-.3/3/.15h -Ba200g200f50/:"  Depth, m":   -C$grid.cpt -O    >> $outfile.ps

	psconvert -Tg -Qt -Qg -A $outfile.ps
	open $outfile.png

fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # 

if [ $makegrid -eq 1 ] ; then

	echo "making GMT-friendly NetCDF grid files for plotting"

	numlines=`wc -l sentry$dive\_turns.xy | awk '{print $1-1}'`
	for line in `seq 1 1 $numlines `; do
		cdpnum=`awk '$1==line {print ($3-$2)+1} ' line=$line linestartsends`
		# make netCDF grid 
		cat su_files/sentry$dive\_line$line\_filt.su | suvlength ns=60000  | sustrip | b2a n1=1 |\
		xyz2grd -ZLBa -R1/$cdpnum\/1/60000 -I1/1 -Gsu_files/sentry$dive\_line$line\_filt.grd
	done

fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # 

if [ $plotgrid -eq 1 ] ; then

	echo "plotting individual CHIRP profiles"
 
	 makecpt -Cgray -T-.8/.8/.01 -Z -I > chirp_gray.cpt

	numlines=`wc -l sentry$dive\_turns.xy | awk '{print $1-1}'`
	for line in `seq 1 1 $numlines  `; do
	
		echo plotting sentry $dive line $line 
		outfile=images/sentry$dive\_line$line\_filt
 
		cdpnum=`awk '$1==line {print ($3-$2)+1} ' line=$line linestartsends`

		cdp1=`awk '$1==line {print $2}' line=$line linestartsends`
		cdp2=`awk '$1==line {print $3}' line=$line linestartsends`

		# 	grab line length in m calculated earlier
		xmax=`awk '$1==line {print $8/1000} ' line=$line linestartsends`
		
		# 	 given horizontal scale, calculate plot width in cm
		
		width=`echo $horiz_scale $cdpnum | awk '{print $1*$2}' `

		# need to know how many samples in each trace to make grid file
		# get sample rate from first jsf/su file, in milliseconds
		#     e.g.  sample rate = 23  microseconds = 0.000023 s
		#     if time window is 0.8 seconds, num samples = 3478
	
		cat su_files/sentry$dive\_line1_filt.su | sugethw key=dt | head -1 | tr -d -c 0-9 > sentry$dive\_dt.dat
		dt=`awk '{print $1}' sentry$dive\_dt.dat `
		numsamp=`echo $t1 $t2 $sr | awk '{print (t2-t1)/(dt/1000000)}' t1=$t1 t2=$t2 dt=$dt `
		vertscale=`echo $chirpheight $numsamp | awk '{print $1/$2}' `
		rgn=-R1/$cdpnum\/1/$numsamp
		
	

		# work out depth axis limits based on times t1 and t2 set at the beginning, assuming velocity set at beginnng
		
		depth1=`echo $t1 | awk '{print ($1/2)*v}' v=$v`
		depth2=`echo $t2 | awk '{print ($1/2)*v}' v=$v`
		   
		rgn2=-R0/$xmax/$depth1\/$depth2
		rgn3=-R0/$xmax/$t1\/$t2
		rgn4=-R1/$cdpnum\/$t1\/$t2     

		# use lon of start/end of line to figure out whether E>W or W>E
		sense=`awk '$1==line {print $6-$4}' line=$line linestartsends | awk '{ if ($1>=0) 	print "1";  else print "0" }'`
	 
		if [ $sense -eq 0 ] ; then

			proj1=-Jx-$horiz_scale\/-$vertscale
			proj2=-JX-$width/-$chirpheight
			proj3=-JX-$width/-$chirpheight
			proj4=-JX-$width/-$chirpheight

			else 

			proj1=-Jx$horiz_scale\/-$vertscale
			proj2=-JX$width/-$chirpheight
			proj3=-JX$width/-$chirpheight
			proj4=-JX$width/-$chirpheight

		fi

	grdimage $rgn  $proj1 su_files/sentry$dive\_line$line\_filt.grd -Cchirp_gray.cpt  -X2 -Y2 -K > $outfile.ps
	psbasemap $proj2 $rgn2 -Ba.2f.1:"Range, km":/a10f2:"Depth below vehicle, m":E -O -K >> $outfile.ps
	psbasemap $proj3  $rgn3 -Ba.2f.1:"Range, km":/a.02f.01:"TWTT below vehicle, s":SW -O -K >> $outfile.ps
	psbasemap $proj4  $rgn4 -Ba500f100:"Trace number":/a.02f.01:"TWTT below vehicle, s":N -O  >> $outfile.ps
	psconvert -A -E500 -Tg -Qt -Qg $outfile.ps
	
	if [ $showplots -eq 1 ] ; then
	open $outfile.png
	fi


	done

fi

# tidy up a bit

rm -f junk.grd temp* *.ps sentry$dive\_dt.dat datalist* 

     
