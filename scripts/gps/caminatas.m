if(~exist('xs_caminatas','var'))
  error(sprintf('Cannot find data! xs_caminatas not defined!\nRefer to comments in caminatas.m for help'))
else
  fprintf('Using data from variable named xs_caminatas\n\t-->VERIFY this is what you expect<--\n\nPress any key to continue...\n');
  pause;
end


% caminata1
caminata1 = { ...
'2012-01-30T23:08:06.000Z' ...
'2012-01-30T23:08:15.000Z' ...
'2012-01-30T23:08:24.000Z' ...
'2012-01-30T23:08:33.000Z' ...
'2012-01-30T23:08:42.000Z' ...
'2012-01-30T23:08:51.000Z'};

% caminata2
caminata2 = { ...
'2012-01-30T23:09:47.000Z' ...
'2012-01-30T23:09:54.000Z' ...
'2012-01-30T23:10:01.000Z' ...
'2012-01-30T23:10:09.000Z' ...
'2012-01-30T23:10:16.000Z' ...
'2012-01-30T23:10:22.000Z'};

% caminata3
caminata3 = { ...
'2012-01-30T23:10:59.000Z' ...
'2012-01-30T23:11:05.000Z' ...
'2012-01-30T23:11:12.000Z' ...
'2012-01-30T23:11:19.000Z' ...
'2012-01-30T23:11:25.000Z' ...
'2012-01-30T23:11:31.000Z'};

caminatas_t = [caminata1;caminata2;caminata3];
cols = 'bgkycr';
e_rel = 576058.037634409; % de la grafica
n_rel = 6135564.0295931;

separate_fig = 1;

for i=1:3
  if(separate_fig)
    figure;
  end
  [easting, northing, elevation, utm_zone, sat] = ...
  gpxlogger_xml_handler(xs_caminatas(i),0);
  easting = easting - e_rel;
  northing = northing - n_rel;
  gps_plot3(easting, northing, elevation, sat,gcf,i-1,0,0,0);
  hold on
  [easting, northing, elevation, utm_zone, sat, ind] = ...
    gpxlogger_time_to_UTM(xs_caminatas(i), caminatas_t(i,:));
  easting = easting - e_rel;
  northing = northing - n_rel;
  plot3(easting,northing,elevation, ...
    sprintf('%c.',cols(i)),'MarkerSize',20, ...
    'HandleVisibility','off');
  plot3(easting,northing,elevation, ...
    'ro','MarkerSize',7, ...
    'HandleVisibility','off');
  title(sprintf('Caminata #%d',i))
  text(easting, northing, elevation, ...
    char('2','3','6','5','4','1'),'FontSize',16, ...
    'BackgroundColor','w','FontWeight','bold', ...
    'Color', cols(i), 'EdgeColor', 'k')
  if(separate_fig)
    legend(sprintf('#%d',i))
  end
end

if(~separate_fig)
  legend('#1', '#2', '#3')
end